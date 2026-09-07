import Foundation

/// Decodes the "data:<mime>;base64,<...>" URIs FirebaseService embeds sighting
/// photo/audio in (see FirebaseService.uploadImage/uploadAudio) — AsyncImage
/// and AVPlayer both load media over URLSession/AVAssetResourceLoader, neither
/// of which reliably fetches a "data:" scheme URL, so callers decode locally
/// instead of handing the string straight to those APIs.
enum DataURI {
    static func decode(_ string: String) -> Data? {
        guard string.hasPrefix("data:"), let commaIndex = string.firstIndex(of: ",") else { return nil }
        return Data(base64Encoded: String(string[string.index(after: commaIndex)...]))
    }

    /// Writes the decoded bytes to a temp file for APIs (like AVPlayer) that
    /// need a file URL rather than raw Data. Returns nil if `string` isn't a
    /// data URI or the write fails.
    static func writeTempFile(_ string: String, extension ext: String) -> URL? {
        guard let data = decode(string) else { return nil }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension(ext)
        do {
            try data.write(to: url)
            return url
        } catch {
            return nil
        }
    }
}
