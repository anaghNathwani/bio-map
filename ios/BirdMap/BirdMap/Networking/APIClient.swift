import Foundation

// Short timeout for foreground requests that surface errors to the user immediately.
private let foregroundSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
    return URLSession(configuration: config)
}()

// Longer timeout for media uploads — the backend runs on Render's free tier,
// which sleeps after 15 minutes idle and takes 30-60s to cold-start on the
// next request, on top of the actual upload time.
private let uploadSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 90
    config.timeoutIntervalForResource = 120
    return URLSession(configuration: config)
}()

enum APIError: Error, LocalizedError {
    case invalidURL
    case missingField(String)
    case httpError(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid server URL"
        case .missingField(let f): return "Missing field in response: \(f)"
        case .httpError(let code): return "Server returned \(code)"
        }
    }
}

struct VisionCandidate: Decodable {
    let species: String
    let confidence: Double
}

private struct MediaUploadResponse: Decodable {
    let photoURL: String?
    let thumbnailURL: String?
    let audioURL: String?
}

// Talks to the backend (Render-hosted, see docs/DEPLOYMENT.md) for: the media
// upload broker (photo/audio -> Supabase Storage, since Firebase Storage now
// requires a paid Blaze plan for any usage), the Google Vision bird-ID proxy,
// and Wikipedia bird info. All Firestore reads/writes (sightings, annotations,
// leaderboard, auth) go through FirebaseService, unaffected by any of this —
// only the underlying media *blobs* moved off Firebase.
final class APIClient {
    static let shared = APIClient()

    let baseURL: String = {
        let configured = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "http://localhost:8000"
        #if targetEnvironment(simulator)
        return configured
        #else
        // A physical device is not the machine running the local Docker
        // Compose backend — "localhost"/"127.0.0.1" there means the device
        // itself, so a Debug build installed on hardware can never reach it.
        // Fall back to the deployed API instead of failing every request.
        if configured.contains("localhost") || configured.contains("127.0.0.1") {
            return "https://birdmap-api.fly.dev"
        }
        return configured
        #endif
    }()

    private func request(_ path: String) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return req
    }

    private func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse, http.statusCode >= 400 else { return }
        throw APIError.httpError(http.statusCode)
    }

    // MARK: - Media upload broker (Supabase Storage via backend, Firebase-token-verified)

    func uploadPhoto(data: Data, sightingID: String, idToken: String) async throws -> (photoURL: String, thumbnailURL: String?) {
        guard let url = URL(string: baseURL + "/media/sightings/\(sightingID)/photo") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, response) = try await uploadSession.data(for: req)
        try checkStatus(response)
        let decoded = try JSONDecoder().decode(MediaUploadResponse.self, from: respData)
        guard let photoURL = decoded.photoURL else { throw APIError.missingField("photoURL") }
        return (photoURL, decoded.thumbnailURL)
    }

    func uploadAudio(data: Data, sightingID: String, idToken: String) async throws -> String {
        guard let url = URL(string: baseURL + "/media/sightings/\(sightingID)/audio") else { throw APIError.invalidURL }
        let boundary = UUID().uuidString
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"audio\"; filename=\"audio.m4a\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: audio/mp4\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (respData, response) = try await uploadSession.data(for: req)
        try checkStatus(response)
        let decoded = try JSONDecoder().decode(MediaUploadResponse.self, from: respData)
        guard let audioURL = decoded.audioURL else { throw APIError.missingField("audioURL") }
        return audioURL
    }

    // MARK: - Vision (Google Cloud proxy)

    func identifyImage(imageData: Data) async throws -> [VisionCandidate] {
        let boundary = UUID().uuidString
        guard let url = URL(string: baseURL + "/vision/identify") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        req.httpBody = body

        let (data, response) = try await foregroundSession.data(for: req)
        try checkStatus(response)
        struct Resp: Decodable { let candidates: [VisionCandidate] }
        return (try? JSONDecoder().decode(Resp.self, from: data))?.candidates ?? []
    }

    // MARK: - Bird Info (Wikipedia direct)

    func birdInfo(species: String) async throws -> BirdInfo {
        try await birdInfoFromWikipedia(species: species)
    }

    private func birdInfoFromWikipedia(species: String) async throws -> BirdInfo {
        let slug = species.replacingOccurrences(of: " ", with: "_")
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? species
        guard let url = URL(string: "https://en.wikipedia.org/api/rest_v1/page/summary/\(slug)") else {
            throw APIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.setValue("BirdMapApp/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await foregroundSession.data(for: req)
        try checkStatus(response)
        struct WikiSummary: Decodable {
            struct Thumbnail: Decodable { let source: String? }
            struct ContentURLs: Decodable {
                struct URLs: Decodable { let page: String? }
                let mobile: URLs?
                let desktop: URLs?
            }
            let extract: String?
            let thumbnail: Thumbnail?
            let content_urls: ContentURLs?
        }
        let wiki = try JSONDecoder().decode(WikiSummary.self, from: data)
        let speciesSlug = species.replacingOccurrences(of: " ", with: "_")
        let wikiURL = wiki.content_urls?.mobile?.page ?? wiki.content_urls?.desktop?.page ?? ""
        return BirdInfo(
            species: species,
            description: wiki.extract ?? "",
            imageURL: wiki.thumbnail?.source,
            wikiURL: wikiURL,
            ebirdURL: "https://ebird.org/search?q=\(species.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? species)",
            allaboutbirdsURL: "https://www.allaboutbirds.org/guide/\(speciesSlug)",
            scientificName: "",
            family: "",
            order: ""
        )
    }
}
