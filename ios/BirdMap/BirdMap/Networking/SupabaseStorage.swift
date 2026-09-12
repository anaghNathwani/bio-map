import Foundation

/// Best-effort fallback upload path for sighting media. Firestore (embedded
/// base64 data URIs, see FirebaseService.uploadImage/uploadAudio) is primary;
/// this uploads the same raw bytes to Supabase Storage as a redundant copy so
/// a client that can't decode/fetch the Firestore copy still has a plain URL
/// to fall back to. Uses the project's public anon key directly — safe to
/// embed client-side by design (Supabase's own model for unauthenticated
/// client access) — against a bucket that must be marked public with an
/// insert policy permitting anon writes, since there's no backend to proxy
/// this through.
enum SupabaseStorage {
    private static let projectURL = "https://erhqaqubnwsptsfjovbp.supabase.co"
    private static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImVyaHFhcXVibndzcHRzZmpvdmJwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODM5ODQ2OTYsImV4cCI6MjA5OTU2MDY5Nn0.9S8KG0SYhfDhGeBjtq_rtotgCe5gb5uIpNAu8e1TY9Q"
    private static let bucket = "birdmap-media"

    /// Uploads `data` to `path` within the bucket and returns its public URL,
    /// or nil on any failure — callers treat this as "no fallback available"
    /// rather than failing the (already-succeeded) primary Firestore write.
    static func uploadFallback(_ data: Data, path: String, contentType: String) async -> String? {
        guard let url = URL(string: "\(projectURL)/storage/v1/object/\(bucket)/\(path)") else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(anonKey)", forHTTPHeaderField: "Authorization")
        request.setValue(anonKey, forHTTPHeaderField: "apikey")
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue("true", forHTTPHeaderField: "x-upsert")
        request.httpBody = data

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                print("[SupabaseStorage] Fallback upload failed: \(response)")
                return nil
            }
            return "\(projectURL)/storage/v1/object/public/\(bucket)/\(path)"
        } catch {
            print("[SupabaseStorage] Fallback upload error: \(error)")
            return nil
        }
    }
}
