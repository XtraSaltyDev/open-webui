import Foundation
import XCTest
@testable import OpenWebUINative

final class OllamaClientTests: XCTestCase {
    func testListModelsCallsTagsEndpointAndDecodesModels() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                capturedRequest = request
                let data = """
                {
                  "models": [
                    { "name": "llama3.2:latest", "model": "llama3.2:latest", "modified_at": "2026-06-02T12:00:00Z", "size": 1234 },
                    { "name": "mistral:latest", "model": "mistral:latest", "modified_at": "2026-06-02T12:00:00Z", "size": 5678 }
                  ]
                }
                """.data(using: .utf8)!
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        let models = try await client.listModels()

        XCTAssertEqual(capturedRequest?.url?.path, "/api/tags")
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(models.map(\.id), ["llama3.2:latest", "mistral:latest"])
        XCTAssertEqual(models.first?.provider, .ollama)
    }

    func testHealthCheckIncludesRuntimeVersionModelCountAndRunningModelCount() async {
        var requestedPaths: [String] = []
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                requestedPaths.append(request.url?.path ?? "")
                let data: Data
                if request.url?.path == "/api/version" {
                    data = #"{"version":"0.12.6"}"#.data(using: .utf8)!
                } else if request.url?.path == "/api/ps" {
                    data = """
                    {
                      "models": [
                        { "name": "llama3.2:latest" }
                      ]
                    }
                    """.data(using: .utf8)!
                } else {
                    data = """
                    {
                      "models": [
                        { "name": "llama3.2:latest", "size": 1234 },
                        { "name": "mistral:latest", "size": 5678 }
                      ]
                    }
                    """.data(using: .utf8)!
                }
                return (data, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        let status = await client.healthCheck()

        XCTAssertEqual(requestedPaths, ["/api/version", "/api/tags", "/api/ps"])
        XCTAssertEqual(status, .available("Ollama 0.12.6 connected (2 models, 1 running)"))
    }

    func testStreamChatPostsChatPayloadAndYieldsContentDeltas() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"{"message":{"role":"assistant","content":"Hello"},"done":false}"#)
                    continuation.yield(#"{"message":{"role":"assistant","content":" world"},"done":false}"#)
                    continuation.yield(#"{"done":true}"#)
                    continuation.finish()
                }
            }
        )

        var chunks: [String] = []
        for try await chunk in client.streamChat(
            model: "llama3.2:latest",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")]
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(capturedRequest?.url?.path, "/api/chat")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "llama3.2:latest")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(chunks, ["Hello", " world"])
    }

    func testStreamCompletionPostsGeneratePayloadAndYieldsResponseDeltas() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"{"response":"Raw","done":false}"#)
                    continuation.yield(#"{"response":" completion","done":false}"#)
                    continuation.yield(#"{"done":true}"#)
                    continuation.finish()
                }
            }
        )

        var chunks: [String] = []
        for try await chunk in client.streamCompletion(
            model: "llama3.2:latest",
            prompt: "Complete this sentence",
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 64)
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(capturedRequest?.url?.path, "/api/generate")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "llama3.2:latest")
        XCTAssertEqual(json?["prompt"] as? String, "Complete this sentence")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        let options = json?["options"] as? [String: Any]
        XCTAssertEqual(options?["temperature"] as? Double, 0.2)
        XCTAssertEqual(options?["top_p"] as? Double, 0.7)
        XCTAssertEqual(options?["num_predict"] as? Int, 64)
        XCTAssertEqual(chunks, ["Raw", " completion"])
    }

    func testStreamChatEventsYieldsFinalTokenUsage() async throws {
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    continuation.yield(#"{"message":{"role":"assistant","content":"Hello"},"done":false}"#)
                    continuation.yield(#"{"done":true,"prompt_eval_count":12,"eval_count":8}"#)
                    continuation.finish()
                }
            }
        )

        var events: [ChatStreamEvent] = []
        for try await event in client.streamChatEvents(
            model: "llama3.2:latest",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")]
        ) {
            events.append(event)
        }

        XCTAssertEqual(events, [
            .content("Hello"),
            .tokenUsage(ChatTokenUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20))
        ])
    }

    func testStreamChatEncodesGenerationOptionsForNativeOllamaAPI() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"{"done":true}"#)
                    continuation.finish()
                }
            }
        )

        for try await _ in client.streamChat(
            model: "llama3.2:latest",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")],
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128)
        ) {}

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let options = json?["options"] as? [String: Any]
        XCTAssertEqual(options?["temperature"] as? Double, 0.2)
        XCTAssertEqual(options?["top_p"] as? Double, 0.7)
        XCTAssertEqual(options?["num_predict"] as? Int, 128)
    }

    func testStreamChatCancelsUnderlyingLineStreamWhenConsumerStops() async throws {
        let cancellation = LineStreamCancellationRecorder()
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        continuation.yield(#"{"message":{"role":"assistant","content":"Hello"},"done":false}"#)
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        continuation.yield(#"{"message":{"role":"assistant","content":" late"},"done":false}"#)
                        continuation.finish()
                    }
                    continuation.onTermination = { termination in
                        if case .cancelled = termination {
                            task.cancel()
                            Task {
                                await cancellation.record()
                            }
                        }
                    }
                }
            }
        )

        for try await _ in client.streamChat(
            model: "llama3.2:latest",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")]
        ) {
            break
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let cancellationCount = await cancellation.currentCount()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testPullModelPostsPullPayloadAndYieldsProgressStatuses() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"{"status":"pulling manifest"}"#)
                    continuation.yield(#"{"status":"downloading","digest":"sha256:abc","total":100,"completed":25}"#)
                    continuation.yield(#"{"status":"success"}"#)
                    continuation.finish()
                }
            }
        )

        var progress: [OllamaModelPullProgress] = []
        for try await event in client.pullModel(named: "gemma3") {
            progress.append(event)
        }

        XCTAssertEqual(capturedRequest?.url?.path, "/api/pull")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gemma3")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(progress.map(\.status), ["pulling manifest", "downloading", "success"])
        XCTAssertEqual(progress[1].completed, 25)
        XCTAssertEqual(progress[1].total, 100)
    }

    func testDeleteModelSendsDeleteRequestWithModelPayload() async throws {
        var capturedRequest: URLRequest?
        let client = OllamaClient(
            baseURL: URL(string: "http://localhost:11434")!,
            dataLoader: { request in
                capturedRequest = request
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        try await client.deleteModel(named: "gemma3")

        XCTAssertEqual(capturedRequest?.url?.path, "/api/delete")
        XCTAssertEqual(capturedRequest?.httpMethod, "DELETE")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gemma3")
    }
}

private actor LineStreamCancellationRecorder {
    private var count = 0

    func record() {
        count += 1
    }

    func currentCount() -> Int {
        count
    }
}
