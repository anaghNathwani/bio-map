import Foundation

final class APIClient {
    static let shared = APIClient()

    // Change to your server IP when testing on device
    var baseURL = "http://localhost:8000"

    private var token: String? {
        UserDefaults.standard.string(forKey: "token")
    }

    private func request(_ path: String, method: String = "GET", body: Data? = nil) -> URLRequest {
        var req = URLRequest(url: URL(string: baseURL + path)!)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        req.httpBody = body
        return req
    }

    // MARK: - Auth

    func register(email: String, username: String, password: String) async throws -> String {
        let body = try JSONEncoder().encode(["email": email, "username": username, "password": password])
        var req = request("/auth/register", method: "POST", body: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode([String: String].self, from: data)
        return resp["access_token"]!
    }

    func login(email: String, password: String) async throws -> String {
        let body = try JSONEncoder().encode(["email": email, "password": password])
        let req = request("/auth/login", method: "POST", body: body)
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode([String: String].self, from: data)
        return resp["access_token"]!
    }

    // MARK: - Sightings

    func sightings(bbox: (minLat: Double, maxLat: Double, minLng: Double, maxLng: Double)? = nil) async throws -> [Sighting] {
        var path = "/sightings?limit=500"
        if let b = bbox {
            path += "&min_lat=\(b.minLat)&max_lat=\(b.maxLat)&min_lng=\(b.minLng)&max_lng=\(b.maxLng)"
        }
        let (data, _) = try await URLSession.shared.data(for: request(path))
        return try JSONDecoder().decode([Sighting].self, from: data)
    }

    func sightingDetail(id: UUID) async throws -> SightingDetail {
        let (data, _) = try await URLSession.shared.data(for: request("/sightings/\(id)"))
        return try JSONDecoder().decode(SightingDetail.self, from: data)
    }

    func uploadSighting(imageData: Data, latitude: Double, longitude: Double, notes: String?) async throws -> String {
        let boundary = UUID().uuidString
        var req = URLRequest(url: URL(string: baseURL + "/sightings")!)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }
        field("latitude", "\(latitude)")
        field("longitude", "\(longitude)")
        if let notes { field("notes", notes) }

        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        req.httpBody = body
        let (data, _) = try await URLSession.shared.data(for: req)
        let resp = try JSONDecoder().decode([String: String].self, from: data)
        return resp["id"]!
    }

    // MARK: - Annotations

    func submitAnnotation(sightingID: UUID, species: String, confidence: Double, behavior: String?, agePlumage: String?) async throws {
        struct Body: Encodable {
            let species: String; let confidence: Double
            let behavior: String?; let age_plumage: String?
        }
        let body = try JSONEncoder().encode(Body(species: species, confidence: confidence, behavior: behavior, age_plumage: agePlumage))
        var req = request("/sightings/\(sightingID)/annotations", method: "POST", body: body)
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Leaderboard

    func leaderboard() async throws -> [LeaderboardEntry] {
        let (data, _) = try await URLSession.shared.data(for: request("/leaderboard"))
        return try JSONDecoder().decode([LeaderboardEntry].self, from: data)
    }

    // MARK: - Model

    func modelVersion() async throws -> ModelVersionInfo {
        let (data, _) = try await URLSession.shared.data(for: request("/model/version"))
        return try JSONDecoder().decode(ModelVersionInfo.self, from: data)
    }

    func modelDownloadURL() async throws -> String {
        let (data, _) = try await URLSession.shared.data(for: request("/model/download"))
        let resp = try JSONDecoder().decode([String: String].self, from: data)
        return resp["url"]!
    }
}
