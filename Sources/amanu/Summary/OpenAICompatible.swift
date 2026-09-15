import Foundation

/// URL construction shared by the OpenAI backend and its no-cost key probe.
/// A compatible server may live below a path such as `/openai/v1`; replacing
/// the path with `appendingPathComponent` would silently discard that prefix.
enum OpenAICompatible {
    static func endpoint(baseURL: String, path: String) -> URL? {
        let base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let parsed = URL(string: base),
              ["http", "https"].contains(parsed.scheme?.lowercased() ?? ""),
              parsed.host != nil
        else { return nil }
        let host = parsed.host?.lowercased()
        let loopback = host == "localhost" || host == "127.0.0.1" || host == "::1"
        // Keys and transcripts must not cross a network in clear text. HTTP
        // remains useful for a server on this Mac, including Ollama's default.
        guard parsed.scheme?.lowercased() == "https" || loopback else { return nil }
        let suffix = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return URL(string: base + "/" + suffix)
    }
}
