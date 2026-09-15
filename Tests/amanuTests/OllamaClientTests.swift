import Foundation
import Testing

@testable import amanu

struct OllamaClientTests {
    @Test("Ollama chat keeps system and user messages separate and disables thinking")
    func chatRequest() throws {
        let request = try OllamaClient.chatRequest(
            baseURL: "https://studio.local:11434/",
            model: "qwen3.5:4b",
            system: "Take meeting notes.",
            prompt: "me: ship it",
            numContext: 16_384)

        #expect(request.url?.absoluteString == "https://studio.local:11434/api/chat")
        #expect(request.httpMethod == "POST")
        let requestBody = try #require(request.httpBody)
        let body = try #require(try JSONSerialization.jsonObject(
            with: requestBody) as? [String: Any])
        #expect(body["model"] as? String == "qwen3.5:4b")
        #expect(body["stream"] as? Bool == false)
        #expect(body["think"] as? Bool == false)
        #expect((body["options"] as? [String: Any])?["num_ctx"] as? Int == 16_384)
        let messages = try #require(body["messages"] as? [[String: String]])
        #expect(messages == [
            ["role": "system", "content": "Take meeting notes."],
            ["role": "user", "content": "me: ship it"],
        ])
    }

    @Test("Ollama reads only message content and surfaces its JSON error")
    func responseParsing() throws {
        let success = Data(###"{"message":{"role":"assistant","content":"## Decisions\nShip."},"thinking":"private"}"###.utf8)
        #expect(try OllamaClient.response(from: success, statusCode: 200)
            == "## Decisions\nShip.")

        let failure = Data(#"{"error":"model 'missing' not found"}"#.utf8)
        #expect(throws: LLMError.self) {
            _ = try OllamaClient.response(from: failure, statusCode: 404)
        }
    }

    @Test("Ollama model discovery retains size and remote provenance")
    func modelDiscovery() throws {
        let data = Data(#"{"models":[{"name":"qwen3.5:4b","size":3400000000},{"name":"gpt-oss:cloud","size":0,"remote_model":"gpt-oss","remote_host":"https://ollama.com"}]}"#.utf8)
        let models = try OllamaClient.models(from: data)

        #expect(models.map(\.name) == ["qwen3.5:4b", "gpt-oss:cloud"])
        #expect(models[0].bytes == 3_400_000_000)
        #expect(!models[0].isRemote)
        #expect(models[1].isRemote)
    }

    @Test("Only loopback Ollama URLs may promise that content stays on this Mac")
    func localURLClassification() {
        #expect(OllamaClient.isLocal(baseURL: "http://127.0.0.1:11434"))
        #expect(OllamaClient.isLocal(baseURL: "http://localhost:11434"))
        #expect(!OllamaClient.isLocal(baseURL: "http://studio.local:11434"))
        #expect(!OllamaClient.isLocal(baseURL: "https://ollama.example"))
    }
}
