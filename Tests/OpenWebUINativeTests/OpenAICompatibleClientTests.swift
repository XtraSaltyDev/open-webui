import Foundation
import XCTest
@testable import OpenWebUINative

final class OpenAICompatibleClientTests: XCTestCase {
    func testListModelsUsesBearerTokenAndDecodesModels() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "Local Gateway",
                kind: .openAICompatible,
                baseURL: "https://gateway.example/v1",
                apiKeySecretID: "secret-1"
            ),
            secretStore: InMemorySecretStore(["secret-1": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                let data = """
                {
                  "object": "list",
                  "data": [
                    { "id": "gpt-4.1-mini", "object": "model", "created": 1710000000, "owned_by": "openai" },
                    { "id": "text-embedding-3-small", "object": "model", "created": 1710000000, "owned_by": "openai" }
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

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://gateway.example/v1/models")
        XCTAssertEqual(capturedRequest?.httpMethod, "GET")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(models.map(\.id), ["gpt-4.1-mini", "text-embedding-3-small"])
        XCTAssertEqual(models.first?.provider, .openAICompatible)
    }

    func testStreamChatPostsChatCompletionPayloadAndYieldsDeltas() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-2"
            ),
            secretStore: InMemorySecretStore(["secret-2": "test-key"]),
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"data: {"choices":[{"delta":{"content":"Hello"}}]}"#)
                    continuation.yield(#"data: {"choices":[{"delta":{"content":" world"}}]}"#)
                    continuation.yield("data: [DONE]")
                    continuation.finish()
                }
            }
        )

        var chunks: [String] = []
        for try await chunk in client.streamChat(
            model: "gpt-4.1-mini",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")]
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/chat/completions")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gpt-4.1-mini")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(chunks, ["Hello", " world"])
    }

    func testStreamCompletionPostsCompletionPayloadAndYieldsTextDeltas() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-2"
            ),
            secretStore: InMemorySecretStore(["secret-2": "test-key"]),
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"data: {"choices":[{"text":"Raw"}]}"#)
                    continuation.yield(#"data: {"choices":[{"text":" completion"}]}"#)
                    continuation.yield("data: [DONE]")
                    continuation.finish()
                }
            }
        )

        var chunks: [String] = []
        for try await chunk in client.streamCompletion(
            model: "gpt-3.5-turbo-instruct",
            prompt: "Complete this sentence",
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 64)
        ) {
            chunks.append(chunk)
        }

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/completions")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gpt-3.5-turbo-instruct")
        XCTAssertEqual(json?["prompt"] as? String, "Complete this sentence")
        XCTAssertEqual(json?["stream"] as? Bool, true)
        XCTAssertEqual(json?["temperature"] as? Double, 0.2)
        XCTAssertEqual(json?["top_p"] as? Double, 0.7)
        XCTAssertEqual(json?["max_tokens"] as? Int, 64)
        XCTAssertEqual(chunks, ["Raw", " completion"])
    }

    func testStreamChatEventsRequestsAndYieldsUsageMetadata() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-2"
            ),
            secretStore: InMemorySecretStore(["secret-2": "test-key"]),
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield(#"data: {"choices":[{"delta":{"content":"Hello"}}]}"#)
                    continuation.yield(#"data: {"choices":[],"usage":{"prompt_tokens":12,"completion_tokens":8,"total_tokens":20}}"#)
                    continuation.yield("data: [DONE]")
                    continuation.finish()
                }
            }
        )

        var events: [ChatStreamEvent] = []
        for try await event in client.streamChatEvents(
            model: "gpt-4.1-mini",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")]
        ) {
            events.append(event)
        }

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        let streamOptions = json?["stream_options"] as? [String: Any]
        XCTAssertEqual(streamOptions?["include_usage"] as? Bool, true)
        XCTAssertEqual(events, [
            .content("Hello"),
            .tokenUsage(ChatTokenUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20))
        ])
    }

    func testStreamChatEncodesGenerationOptionsForOpenAICompatibleAPI() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-2"
            ),
            secretStore: InMemorySecretStore(["secret-2": "test-key"]),
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { request in
                capturedRequest = request
                return AsyncThrowingStream { continuation in
                    continuation.yield("data: [DONE]")
                    continuation.finish()
                }
            }
        )

        for try await _ in client.streamChat(
            model: "gpt-4.1-mini",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")],
            options: ProviderChatOptions(temperature: 0.2, topP: 0.7, maxTokens: 128)
        ) {}

        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["temperature"] as? Double, 0.2)
        XCTAssertEqual(json?["top_p"] as? Double, 0.7)
        XCTAssertEqual(json?["max_tokens"] as? Int, 128)
    }

    func testStreamChatCancelsUnderlyingLineStreamWhenConsumerStops() async throws {
        let cancellation = LineStreamCancellationRecorder()
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-2"
            ),
            secretStore: InMemorySecretStore(["secret-2": "test-key"]),
            dataLoader: { request in
                (Data(), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    let task = Task {
                        continuation.yield(#"data: {"choices":[{"delta":{"content":"Hello"}}]}"#)
                        try? await Task.sleep(nanoseconds: 300_000_000)
                        continuation.yield(#"data: {"choices":[{"delta":{"content":" late"}}]}"#)
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
            model: "gpt-4.1-mini",
            messages: [ProviderChatMessage(role: "user", content: "Say hello")]
        ) {
            break
        }
        try await Task.sleep(nanoseconds: 50_000_000)

        let cancellationCount = await cancellation.currentCount()
        XCTAssertEqual(cancellationCount, 1)
    }

    func testCreateEmbeddingsPostsEmbeddingPayloadAndDecodesVector() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-3"
            ),
            secretStore: InMemorySecretStore(["secret-3": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                let data = """
                {
                  "object": "list",
                  "data": [
                    { "object": "embedding", "index": 0, "embedding": [0.1, -0.2, 0.3] }
                  ],
                  "model": "text-embedding-3-small"
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

        let vectors = try await client.createEmbeddings(model: "text-embedding-3-small", input: ["hello"])

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/embeddings")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "text-embedding-3-small")
        XCTAssertEqual(json?["input"] as? [String], ["hello"])
        XCTAssertEqual(vectors, [[0.1, -0.2, 0.3]])
    }

    func testGenerateImagesPostsImagePayloadAndDecodesBase64Images() async throws {
        var capturedRequest: URLRequest?
        let imageData = Data("fake-png".utf8)
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-4"
            ),
            secretStore: InMemorySecretStore(["secret-4": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                let data = """
                {
                  "created": 1713833628,
                  "data": [
                    {
                      "b64_json": "\(imageData.base64EncodedString())",
                      "revised_prompt": "A polished native macOS app icon"
                    }
                  ],
                  "output_format": "png",
                  "size": "1024x1024",
                  "quality": "high"
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

        let result = try await client.generateImages(
            request: ImageGenerationRequest(
                model: "gpt-image-1",
                prompt: "Native macOS app icon",
                size: "1024x1024",
                quality: "high",
                count: 1
            )
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/images/generations")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gpt-image-1")
        XCTAssertEqual(json?["prompt"] as? String, "Native macOS app icon")
        XCTAssertEqual(json?["size"] as? String, "1024x1024")
        XCTAssertEqual(json?["quality"] as? String, "high")
        XCTAssertEqual(json?["n"] as? Int, 1)
        XCTAssertEqual(result.images.map(\.data), [imageData])
        XCTAssertEqual(result.images.map(\.revisedPrompt), ["A polished native macOS app icon"])
        XCTAssertEqual(result.outputFormat, "png")
        XCTAssertEqual(result.size, "1024x1024")
        XCTAssertEqual(result.quality, "high")
    }

    func testEditImagePostsMultipartPayloadAndDecodesBase64Images() async throws {
        var capturedRequest: URLRequest?
        let sourceImage = Data("source-png".utf8)
        let maskImage = Data("mask-png".utf8)
        let editedImage = Data("edited-png".utf8)
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-5"
            ),
            secretStore: InMemorySecretStore(["secret-5": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                let data = """
                {
                  "created": 1713833628,
                  "data": [
                    {
                      "b64_json": "\(editedImage.base64EncodedString())",
                      "revised_prompt": "Make the toolbar calmer"
                    }
                  ],
                  "output_format": "png",
                  "size": "1024x1024",
                  "quality": "high"
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

        let result = try await client.editImage(
            request: ImageEditRequest(
                model: "gpt-image-1",
                prompt: "Make the toolbar calmer",
                imageData: sourceImage,
                imageFileName: "source.png",
                imageContentType: "image/png",
                maskData: maskImage,
                maskFileName: "mask.png",
                maskContentType: "image/png",
                size: "1024x1024",
                quality: "high",
                count: 1
            )
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/images/edits")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let contentType = try XCTUnwrap(capturedRequest?.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(data: try XCTUnwrap(capturedRequest?.httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("name=\"model\"") ?? false)
        XCTAssertTrue(body?.contains("gpt-image-1") ?? false)
        XCTAssertTrue(body?.contains("name=\"prompt\"") ?? false)
        XCTAssertTrue(body?.contains("Make the toolbar calmer") ?? false)
        XCTAssertTrue(body?.contains("name=\"size\"") ?? false)
        XCTAssertTrue(body?.contains("1024x1024") ?? false)
        XCTAssertTrue(body?.contains("name=\"quality\"") ?? false)
        XCTAssertTrue(body?.contains("high") ?? false)
        XCTAssertTrue(body?.contains("name=\"n\"") ?? false)
        XCTAssertTrue(body?.contains("filename=\"source.png\"") ?? false)
        XCTAssertTrue(body?.contains("Content-Type: image/png") ?? false)
        XCTAssertTrue(body?.contains("source-png") ?? false)
        XCTAssertTrue(body?.contains("name=\"mask\"") ?? false)
        XCTAssertTrue(body?.contains("filename=\"mask.png\"") ?? false)
        XCTAssertTrue(body?.contains("mask-png") ?? false)
        XCTAssertEqual(result.images.map(\.data), [editedImage])
        XCTAssertEqual(result.images.map(\.revisedPrompt), ["Make the toolbar calmer"])
        XCTAssertEqual(result.outputFormat, "png")
        XCTAssertEqual(result.size, "1024x1024")
        XCTAssertEqual(result.quality, "high")
    }

    func testVaryImagePostsMultipartPayloadAndDecodesBase64Images() async throws {
        var capturedRequest: URLRequest?
        let sourceImage = Data("source-png".utf8)
        let variationImage = Data("variation-png".utf8)
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-6"
            ),
            secretStore: InMemorySecretStore(["secret-6": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                let data = """
                {
                  "created": 1713833628,
                  "data": [
                    {
                      "b64_json": "\(variationImage.base64EncodedString())"
                    }
                  ],
                  "output_format": "png",
                  "size": "1024x1024"
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

        let result = try await client.varyImage(
            request: ImageVariationRequest(
                model: "dall-e-2",
                imageData: sourceImage,
                imageFileName: "source.png",
                imageContentType: "image/png",
                size: "1024x1024",
                count: 1
            )
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/images/variations")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let contentType = try XCTUnwrap(capturedRequest?.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(data: try XCTUnwrap(capturedRequest?.httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("name=\"model\"") ?? false)
        XCTAssertTrue(body?.contains("dall-e-2") ?? false)
        XCTAssertTrue(body?.contains("name=\"size\"") ?? false)
        XCTAssertTrue(body?.contains("1024x1024") ?? false)
        XCTAssertTrue(body?.contains("name=\"n\"") ?? false)
        XCTAssertTrue(body?.contains("name=\"response_format\"") ?? false)
        XCTAssertTrue(body?.contains("b64_json") ?? false)
        XCTAssertTrue(body?.contains("filename=\"source.png\"") ?? false)
        XCTAssertTrue(body?.contains("Content-Type: image/png") ?? false)
        XCTAssertTrue(body?.contains("source-png") ?? false)
        XCTAssertEqual(result.images.map(\.data), [variationImage])
        XCTAssertEqual(result.outputFormat, "png")
        XCTAssertEqual(result.size, "1024x1024")
    }

    func testTranscribeAudioPostsMultipartPayloadAndDecodesText() async throws {
        var capturedRequest: URLRequest?
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-6"
            ),
            secretStore: InMemorySecretStore(["secret-6": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                return (
                    Data("Build native audio support.".utf8),
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        let result = try await client.transcribeAudio(
            request: AudioTranscriptionRequest(
                model: "gpt-4o-mini-transcribe",
                audioData: Data("audio-bytes".utf8),
                fileName: "meeting.wav",
                contentType: "audio/wav",
                prompt: "This is a product planning meeting.",
                language: "en"
            )
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        let contentType = try XCTUnwrap(capturedRequest?.value(forHTTPHeaderField: "Content-Type"))
        XCTAssertTrue(contentType.hasPrefix("multipart/form-data; boundary="))
        let body = String(data: try XCTUnwrap(capturedRequest?.httpBody), encoding: .utf8)
        XCTAssertTrue(body?.contains("name=\"model\"") ?? false)
        XCTAssertTrue(body?.contains("gpt-4o-mini-transcribe") ?? false)
        XCTAssertTrue(body?.contains("name=\"response_format\"") ?? false)
        XCTAssertTrue(body?.contains("text") ?? false)
        XCTAssertTrue(body?.contains("name=\"prompt\"") ?? false)
        XCTAssertTrue(body?.contains("product planning meeting") ?? false)
        XCTAssertTrue(body?.contains("name=\"language\"") ?? false)
        XCTAssertTrue(body?.contains("en") ?? false)
        XCTAssertTrue(body?.contains("filename=\"meeting.wav\"") ?? false)
        XCTAssertTrue(body?.contains("Content-Type: audio/wav") ?? false)
        XCTAssertTrue(body?.contains("audio-bytes") ?? false)
        XCTAssertEqual(result.text, "Build native audio support.")
    }

    func testSynthesizeSpeechPostsJSONPayloadAndReturnsAudioBytes() async throws {
        var capturedRequest: URLRequest?
        let speechData = Data("mp3-bytes".utf8)
        let client = OpenAICompatibleClient(
            configuration: ProviderConfiguration(
                id: UUID(),
                name: "OpenAI",
                kind: .openAICompatible,
                baseURL: "https://api.openai.com/v1",
                apiKeySecretID: "secret-7"
            ),
            secretStore: InMemorySecretStore(["secret-7": "test-key"]),
            dataLoader: { request in
                capturedRequest = request
                return (
                    speechData,
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
                )
            },
            lineStreamLoader: { _ in
                AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }
        )

        let result = try await client.synthesizeSpeech(
            request: SpeechSynthesisRequest(
                model: "gpt-4o-mini-tts",
                input: "Welcome to the native app.",
                voice: "coral",
                instructions: "Warm and concise.",
                responseFormat: "mp3"
            )
        )

        XCTAssertEqual(capturedRequest?.url?.absoluteString, "https://api.openai.com/v1/audio/speech")
        XCTAssertEqual(capturedRequest?.httpMethod, "POST")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
        XCTAssertEqual(capturedRequest?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as? [String: Any]
        XCTAssertEqual(json?["model"] as? String, "gpt-4o-mini-tts")
        XCTAssertEqual(json?["input"] as? String, "Welcome to the native app.")
        XCTAssertEqual(json?["voice"] as? String, "coral")
        XCTAssertEqual(json?["instructions"] as? String, "Warm and concise.")
        XCTAssertEqual(json?["response_format"] as? String, "mp3")
        XCTAssertEqual(result.audioData, speechData)
        XCTAssertEqual(result.outputFormat, "mp3")
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
