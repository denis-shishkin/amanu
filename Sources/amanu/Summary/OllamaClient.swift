import Foundation

/// The small part of Ollama's native API Amanu needs. Keeping request
/// construction here makes the privacy boundary explicit and lets Setup use
/// the same configured server as the summarizer.
enum OllamaClient {
    struct Model: Equatable, Sendable {
        let name: String
        let bytes: Int
        let remoteModel: String?
        let remoteHost: String?

        var isRemote: Bool { remoteModel != nil || remoteHost != nil }
    }

    static func chatRequest(
        baseURL: String,
        model: String,
        system: String,
        prompt: String,
        numContext: Int = 16_384
    ) throws -> URLRequest {
        guard let url = endpoint(baseURL: baseURL, path: "api/chat") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 1_800
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": prompt],
            ],
            "stream": false,
            "think": false,
            "options": ["temperature": 0.2, "num_ctx": numContext],
        ])
        return request
    }

    static func response(from data: Data, statusCode: Int) throws -> String {
        guard (200..<300).contains(statusCode) else {
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let message = json?["error"] as? String
                ?? String(decoding: data.prefix(400), as: UTF8.self)
            throw LLMError.http(statusCode, message)
        }
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw LLMError.malformedResponse("ollama") }
        guard !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.emptyResponse("ollama")
        }
        return content
    }

    static func models(from data: Data) throws -> [Model] {
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let rows = json["models"] as? [[String: Any]]
        else { throw LLMError.malformedResponse("ollama") }
        return rows.compactMap { row in
            guard let name = row["name"] as? String else { return nil }
            return Model(
                name: name,
                bytes: (row["size"] as? NSNumber)?.intValue ?? 0,
                remoteModel: row["remote_model"] as? String,
                remoteHost: row["remote_host"] as? String)
        }
    }

    static func chat(
        baseURL: String,
        model: String,
        system: String,
        prompt: String,
        session: URLSession = .shared
    ) async throws -> String {
        let request = try chatRequest(
            baseURL: baseURL, model: model, system: system, prompt: prompt)
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        return try self.response(from: data, statusCode: statusCode)
    }

    static func listModels(
        baseURL: String,
        timeout: TimeInterval = 2,
        session: URLSession = .shared
    ) async throws -> [Model] {
        guard let url = endpoint(baseURL: baseURL, path: "api/tags") else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(statusCode) else {
            throw LLMError.http(statusCode, String(decoding: data.prefix(400), as: UTF8.self))
        }
        return try models(from: data)
    }

    static func isLocal(baseURL: String) -> Bool {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    private static func endpoint(baseURL: String, path: String) -> URL? {
        OpenAICompatible.endpoint(baseURL: baseURL, path: path)
    }
}
