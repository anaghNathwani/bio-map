import Foundation

// Shared session configured for battery efficiency:
// - waitsForConnectivity avoids repeated failed attempts when offline
// - allows the OS to coalesce requests at opportunistic moments
private let batteryEfficientSession: URLSession = {
    let config = URLSessionConfiguration.default
    config.waitsForConnectivity = true
    config.timeoutIntervalForResource = 60
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

final class APIClient {
    static let shared = APIClient()

    // Reads API base URL from Info.plist key "API_BASE_URL".
    // Set this per-scheme in Xcode: Product → Scheme → Edit → Run → Arguments.
    // Defaults to localhost for simulator runs.
    let baseURL: String = {
        Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String
            ?? "http://localhost:8000"
    }()

    weak var environment: AppEnvironment?

    private var token: String? { KeychainHelper.load(for: "auth_token") }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) throws -> URLRequest {
        guard let url = URL(string: baseURL + path) else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        return req
    }

    private func checkStatus(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        if http.statusCode == 401 {
            environment?.handleUnauthorized()
            throw APIError.httpError(401)
        }
        if http.statusCode >= 400 { throw APIError.httpError(http.statusCode) }
    }

    // MARK: - Auth

    struct AuthResponse: Decodable {
        let access_token: String
        let username: String
    }

    func register(email: String, username: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(["email": email, "username": username, "password": password])
        let req = try request("/auth/register", method: "POST", body: body)
        let (data, response) = try await batteryEfficientSession.data(for: req)
        try checkStatus(response)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    func login(email: String, password: String) async throws -> AuthResponse {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let req = try request("/auth/login", method: "POST", body: body)
        let (data, response) = try await batteryEfficientSession.data(for: req)
        try checkStatus(response)
        return try JSONDecoder().decode(AuthResponse.self, from: data)
    }

    // MARK: - Sightings

    func sightings(bbox: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? = nil) async throws -> [Sighting] {
        var path = "/sightings?limit=500"
        if let b = bbox {
            path += "&min_lat=\(b.minLat)&max_lat=\(b.maxLat)&min_lng=\(b.minLng)&max_lng=\(b.maxLng)"
        }
        let (data, response) = try await batteryEfficientSession.data(for: try request(path))
        try checkStatus(response)
        return try JSONDecoder().decode([Sighting].self, from: data)
    }

    func sightingDetail(id: UUID) async throws -> SightingDetail {
        let (data, response) = try await batteryEfficientSession.data(for: try request("/sightings/\(id)"))
        try checkStatus(response)
        return try JSONDecoder().decode(SightingDetail.self, from: data)
    }

    func uploadSighting(imageData: Data, latitude: Double, longitude: Double, notes: String?) async throws -> String {
        let boundary = UUID().uuidString
        guard let url = URL(string: baseURL + "/sightings") else { throw APIError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8) ?? Data())
            body.append("\(value)\r\n".data(using: .utf8) ?? Data())
        }
        field("latitude", "\(latitude)")
        field("longitude", "\(longitude)")
        if let notes { field("notes", notes) }

        body.append("--\(boundary)\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8) ?? Data())
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8) ?? Data())
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8) ?? Data())

        req.httpBody = body
        let (data, response) = try await batteryEfficientSession.data(for: req)
        try checkStatus(response)
        let resp = try JSONDecoder().decode([String: String].self, from: data)
        guard let id = resp["id"] else { throw APIError.missingField("id") }
        return id
    }

    // MARK: - Annotations

    func submitAnnotation(sightingID: UUID, species: String, confidence: Double, behavior: String?, agePlumage: String?) async throws {
        struct Body: Encodable {
            let species: String; let confidence: Double
            let behavior: String?; let age_plumage: String?
        }
        let body = try JSONEncoder().encode(Body(species: species, confidence: confidence, behavior: behavior, age_plumage: agePlumage))
        let req = try request("/sightings/\(sightingID)/annotations", method: "POST", body: body)
        let (_, response) = try await batteryEfficientSession.data(for: req)
        try checkStatus(response)
    }

    // MARK: - Leaderboard

    func leaderboard() async throws -> [LeaderboardEntry] {
        let (data, response) = try await batteryEfficientSession.data(for: try request("/leaderboard"))
        try checkStatus(response)
        return try JSONDecoder().decode([LeaderboardEntry].self, from: data)
    }

    // MARK: - Model

    func modelVersion() async throws -> ModelVersionInfo {
        let (data, response) = try await batteryEfficientSession.data(for: try request("/model/version"))
        try checkStatus(response)
        return try JSONDecoder().decode(ModelVersionInfo.self, from: data)
    }

    func modelDownloadURL() async throws -> String {
        let (data, response) = try await batteryEfficientSession.data(for: try request("/model/download"))
        try checkStatus(response)
        let resp = try JSONDecoder().decode([String: String].self, from: data)
        guard let url = resp["url"] else { throw APIError.missingField("url") }
        return url
    }
}
