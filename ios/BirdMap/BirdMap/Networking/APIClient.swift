import Foundation

// Short timeout for foreground requests that surface errors to the user immediately.
private let foregroundSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.timeoutIntervalForRequest = 15
    config.timeoutIntervalForResource = 30
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

// Talks to the backend for the optional Google Vision bird-ID proxy; media
// blobs (photo/audio) are compressed client-side and embedded as base64
// directly in the Firestore sighting doc by FirebaseService, not this client
// or any Storage SDK — see docs/DEPLOYMENT.md. Wikipedia bird info is
// fetched directly too, not proxied.
final class APIClient {
    static let shared = APIClient()

    // Only gates the optional Vision proxy now that media uploads no longer
    // touch a backend at all. No backend is actually deployed anywhere (see
    // docs/DEPLOYMENT.md), so this only matters if/when that backend exists;
    // identifyImage() call sites already treat it as optional (`try?`). For
    // local testing against docker-compose from a physical device, "localhost"
    // won't resolve to the Mac — use the scheme's "Arguments Passed On Launch"
    // to set -API_BASE_URL_OVERRIDE "http://<mac-lan-ip>:8000" instead.
    let baseURL: String = {
        if let override = UserDefaults.standard.string(forKey: "API_BASE_URL_OVERRIDE"),
           !override.isEmpty {
            return override
        }
        return Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "http://localhost:8000"
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
