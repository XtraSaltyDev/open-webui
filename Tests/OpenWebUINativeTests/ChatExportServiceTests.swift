import Foundation
import XCTest
@testable import OpenWebUINative

final class ChatExportServiceTests: XCTestCase {
    func testMarkdownExportIncludesTitleModelsRolesAndContent() throws {
        let thread = ChatThread(
            title: "Research Notes",
            createdAt: Date(timeIntervalSince1970: 10),
            updatedAt: Date(timeIntervalSince1970: 20),
            providerID: ProviderConfiguration.defaultOllamaID,
            modelIDs: ["llama3.2:latest"],
            messages: [
                ChatMessage(role: .user, content: "Summarize this."),
                ChatMessage(role: .assistant, content: "Here is a summary.", modelID: "llama3.2:latest", rating: .positive)
            ]
        )

        let markdown = ChatExportService().markdown(for: thread)

        XCTAssertTrue(markdown.contains("# Research Notes"))
        XCTAssertTrue(markdown.contains("Models: llama3.2:latest"))
        XCTAssertTrue(markdown.contains("## User"))
        XCTAssertTrue(markdown.contains("Summarize this."))
        XCTAssertTrue(markdown.contains("## Assistant"))
        XCTAssertTrue(markdown.contains("Here is a summary."))
        XCTAssertTrue(markdown.contains("Rating: Positive"))
    }

    func testJSONExportRoundTripsThread() throws {
        let thread = ChatThread(
            title: "Export Me",
            modelIDs: ["gpt-4.1-mini"],
            messages: [
                ChatMessage(role: .user, content: "Hello"),
                ChatMessage(
                    role: .assistant,
                    content: "Hi.",
                    modelID: "gpt-4.1-mini",
                    generationMetrics: ChatGenerationMetrics(
                        startedAt: Date(timeIntervalSince1970: 100),
                        completedAt: Date(timeIntervalSince1970: 101)
                    ),
                    tokenUsage: ChatTokenUsage(promptTokens: 12, completionTokens: 8, totalTokens: 20)
                )
            ]
        )

        let data = try ChatExportService().jsonData(for: thread)
        let decoded = try JSONDecoder.openWebUIDecoder.decode(ChatThread.self, from: data)

        XCTAssertEqual(decoded.title, "Export Me")
        XCTAssertEqual(decoded.modelIDs, ["gpt-4.1-mini"])
        XCTAssertEqual(decoded.messages.first?.content, "Hello")
        XCTAssertEqual(decoded.messages.last?.generationMetrics?.durationSeconds, 1)
        XCTAssertEqual(decoded.messages.last?.tokenUsage?.totalTokens, 20)
    }

    func testOpenWebUIJSONExportBuildsImportEnvelopeWithLinearHistory() throws {
        let threadID = UUID(uuidString: "00000000-0000-0000-0000-000000000111")!
        let userMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000000222")!
        let assistantMessageID = UUID(uuidString: "00000000-0000-0000-0000-000000000333")!
        let folderID = UUID(uuidString: "00000000-0000-0000-0000-000000000444")!
        let thread = ChatThread(
            id: threadID,
            title: "Open WebUI Ready",
            userID: "native-user",
            createdAt: Date(timeIntervalSince1970: 100),
            updatedAt: Date(timeIntervalSince1970: 200),
            folderID: folderID,
            modelIDs: ["llama3.2:latest"],
            tags: ["migration"],
            isPinned: true,
            messages: [
                ChatMessage(
                    id: userMessageID,
                    role: .user,
                    content: "Can Open WebUI import this?",
                    createdAt: Date(timeIntervalSince1970: 101)
                ),
                ChatMessage(
                    id: assistantMessageID,
                    role: .assistant,
                    content: "Yes, through its chat import route.",
                    modelID: "llama3.2:latest",
                    createdAt: Date(timeIntervalSince1970: 102),
                    rating: .negative
                )
            ]
        )

        let data = try ChatExportService().openWebUIJSONData(for: [thread])
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chats = try XCTUnwrap(envelope["chats"] as? [[String: Any]])
        let record = try XCTUnwrap(chats.first)
        let chat = try XCTUnwrap(record["chat"] as? [String: Any])
        let history = try XCTUnwrap(chat["history"] as? [String: Any])
        let messages = try XCTUnwrap(history["messages"] as? [String: [String: Any]])
        let userMessage = try XCTUnwrap(messages[userMessageID.uuidString])
        let assistantMessage = try XCTUnwrap(messages[assistantMessageID.uuidString])

        XCTAssertEqual(chats.count, 1)
        XCTAssertEqual(record["folder_id"] as? String, folderID.uuidString)
        XCTAssertEqual(record["created_at"] as? Int, 100)
        XCTAssertEqual(record["updated_at"] as? Int, 200)
        XCTAssertEqual(record["pinned"] as? Bool, true)
        XCTAssertEqual((record["meta"] as? [String: Any])?["tags"] as? [String], ["migration"])
        XCTAssertEqual(chat["title"] as? String, "Open WebUI Ready")
        XCTAssertEqual(chat["models"] as? [String], ["llama3.2:latest"])
        XCTAssertEqual(history["currentId"] as? String, assistantMessageID.uuidString)
        XCTAssertEqual(userMessage["parentId"] as? NSNull, NSNull())
        XCTAssertEqual(userMessage["childrenIds"] as? [String], [assistantMessageID.uuidString])
        XCTAssertEqual(userMessage["role"] as? String, "user")
        XCTAssertEqual(userMessage["content"] as? String, "Can Open WebUI import this?")
        XCTAssertEqual(assistantMessage["parentId"] as? String, userMessageID.uuidString)
        XCTAssertEqual(assistantMessage["childrenIds"] as? [String], [])
        XCTAssertEqual(assistantMessage["role"] as? String, "assistant")
        XCTAssertEqual(assistantMessage["model"] as? String, "llama3.2:latest")
        XCTAssertEqual((assistantMessage["annotation"] as? [String: Any])?["rating"] as? Int, -1)
    }

    func testImportJSONDecodesExportedThread() throws {
        let exportedThread = ChatThread(
            title: "Import Me",
            modelIDs: ["llama3.2:latest"],
            messages: [
                ChatMessage(role: .user, content: "Restore this chat.")
            ]
        )
        let service = ChatExportService()
        let data = try service.jsonData(for: exportedThread)

        let importedThread = try service.thread(fromJSONData: data)

        XCTAssertEqual(importedThread.title, "Import Me")
        XCTAssertEqual(importedThread.modelIDs, ["llama3.2:latest"])
        XCTAssertEqual(importedThread.messages.first?.content, "Restore this chat.")
    }

    func testImportJSONDecodesOpenWebUIChatHistoryRecordActiveBranch() throws {
        let data = Data(
            """
            {
              "id": "00000000-0000-0000-0000-000000000abc",
              "user_id": "user-123",
              "title": "Open WebUI Export",
              "created_at": 1710000000,
              "updated_at": 1710000300,
              "archived": false,
              "pinned": true,
              "folder_id": "00000000-0000-0000-0000-000000000def",
              "meta": { "tags": ["research", "imported"] },
              "chat": {
                "models": ["llama3.2:latest", "qwen3:latest"],
                "history": {
                  "currentId": "assistant-b",
                  "messages": {
                    "user-root": {
                      "id": "user-root",
                      "parentId": null,
                      "childrenIds": ["assistant-a", "assistant-b"],
                      "role": "user",
                      "content": "Compare these options.",
                      "timestamp": 1710000001
                    },
                    "assistant-a": {
                      "id": "assistant-a",
                      "parentId": "user-root",
                      "childrenIds": [],
                      "role": "assistant",
                      "content": "Inactive branch.",
                      "model": "llama3.2:latest",
                      "timestamp": 1710000002
                    },
                    "assistant-b": {
                      "id": "assistant-b",
                      "parentId": "user-root",
                      "childrenIds": [],
                      "role": "assistant",
                      "content": [
                        { "type": "text", "text": "Active branch answer." }
                      ],
                      "model": "qwen3:latest",
                      "timestamp": 1710000003,
                      "annotation": { "rating": 1 }
                    }
                  }
                }
              }
            }
            """.utf8
        )

        let importedThread = try ChatExportService().thread(fromJSONData: data)

        XCTAssertEqual(importedThread.id, UUID(uuidString: "00000000-0000-0000-0000-000000000abc"))
        XCTAssertEqual(importedThread.userID, "user-123")
        XCTAssertEqual(importedThread.title, "Open WebUI Export")
        XCTAssertEqual(importedThread.createdAt, Date(timeIntervalSince1970: 1_710_000_000))
        XCTAssertEqual(importedThread.updatedAt, Date(timeIntervalSince1970: 1_710_000_300))
        XCTAssertEqual(importedThread.folderID, UUID(uuidString: "00000000-0000-0000-0000-000000000def"))
        XCTAssertEqual(importedThread.tags, ["research", "imported"])
        XCTAssertTrue(importedThread.isPinned)
        XCTAssertEqual(importedThread.modelIDs, ["llama3.2:latest", "qwen3:latest"])
        XCTAssertEqual(importedThread.messages.map(\.content), ["Compare these options.", "Active branch answer."])
        XCTAssertEqual(importedThread.messages.last?.modelID, "qwen3:latest")
        XCTAssertEqual(importedThread.messages.last?.rating, .positive)
    }

    func testImportJSONDecodesOpenWebUIChatsEnvelope() throws {
        let data = Data(
            """
            {
              "chats": [
                {
                  "chat": {
                    "history": {
                      "currentId": "message-1",
                      "messages": {
                        "message-1": {
                          "id": "message-1",
                          "parentId": null,
                          "role": "user",
                          "content": "Envelope import.",
                          "timestamp": 1710000100
                        }
                      }
                    }
                  },
                  "created_at": 1710000100,
                  "updated_at": 1710000100
                }
              ]
            }
            """.utf8
        )

        let importedThreads = try ChatExportService().threads(fromJSONData: data)

        XCTAssertEqual(importedThreads.count, 1)
        XCTAssertEqual(importedThreads.first?.title, "Imported Chat")
        XCTAssertEqual(importedThreads.first?.messages.first?.content, "Envelope import.")
    }

    func testImportJSONDecodesOpenWebUIDataEnvelopeAndSnakeCaseCurrentID() throws {
        let data = Data(
            """
            {
              "data": [
                {
                  "chat": {
                    "title": "Data Envelope",
                    "models": ["qwen3:latest"],
                    "history": {
                      "current_id": "assistant-1",
                      "messages": {
                        "user-1": {
                          "id": "user-1",
                          "parent_id": null,
                          "children_ids": ["assistant-1"],
                          "role": "user",
                          "content": "Use the attached scan.",
                          "timestamp": 1710000200,
                          "files": [
                            {
                              "id": "00000000-0000-0000-0000-00000000f111",
                              "meta": {
                                "name": "scan.pdf",
                                "content_type": "application/pdf",
                                "size": 42
                              },
                              "data": {
                                "content": "OCR text from scanned PDF."
                              }
                            }
                          ]
                        },
                        "assistant-1": {
                          "id": "assistant-1",
                          "parent_id": "user-1",
                          "children_ids": [],
                          "role": "assistant",
                          "content": "I can search that text now.",
                          "model": "qwen3:latest",
                          "timestamp": 1710000201
                        }
                      }
                    }
                  },
                  "created_at": 1710000200,
                  "updated_at": 1710000201
                }
              ]
            }
            """.utf8
        )

        let importedThreads = try ChatExportService().threads(fromJSONData: data)
        let userMessage = try XCTUnwrap(importedThreads.first?.messages.first)
        let attachment = try XCTUnwrap(userMessage.attachments.first)

        XCTAssertEqual(importedThreads.count, 1)
        XCTAssertEqual(importedThreads.first?.title, "Data Envelope")
        XCTAssertEqual(importedThreads.first?.messages.map(\.content), [
            "Use the attached scan.",
            "I can search that text now."
        ])
        XCTAssertEqual(attachment.id, UUID(uuidString: "00000000-0000-0000-0000-00000000f111"))
        XCTAssertEqual(attachment.fileName, "scan.pdf")
        XCTAssertEqual(attachment.contentType, "application/pdf")
        XCTAssertEqual(attachment.byteCount, 42)
        XCTAssertEqual(attachment.textContent, "OCR text from scanned PDF.")
    }

    func testOpenWebUIJSONExportIncludesAttachmentMetadataForRoundTrip() throws {
        let messageID = UUID(uuidString: "00000000-0000-0000-0000-000000000555")!
        let attachmentID = UUID(uuidString: "00000000-0000-0000-0000-000000000666")!
        let thread = ChatThread(
            title: "Attachment Export",
            messages: [
                ChatMessage(
                    id: messageID,
                    role: .user,
                    content: "Use this file.",
                    attachments: [
                        ChatAttachment(
                            id: attachmentID,
                            fileName: "brief.md",
                            contentType: "text/markdown",
                            byteCount: 19,
                            textContent: "# Brief\nSource text."
                        )
                    ]
                )
            ]
        )

        let data = try ChatExportService().openWebUIJSONData(for: thread)
        let roundTripped = try ChatExportService().threads(fromJSONData: data)
        let attachment = try XCTUnwrap(roundTripped.first?.messages.first?.attachments.first)
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let chats = try XCTUnwrap(envelope["chats"] as? [[String: Any]])
        let chat = try XCTUnwrap(chats.first?["chat"] as? [String: Any])
        let history = try XCTUnwrap(chat["history"] as? [String: Any])
        let messages = try XCTUnwrap(history["messages"] as? [String: [String: Any]])
        let exportedMessage = try XCTUnwrap(messages[messageID.uuidString])
        let files = try XCTUnwrap(exportedMessage["files"] as? [[String: Any]])
        let exportedFile = try XCTUnwrap(files.first)

        XCTAssertEqual(attachment.id, attachmentID)
        XCTAssertEqual(attachment.fileName, "brief.md")
        XCTAssertEqual(attachment.contentType, "text/markdown")
        XCTAssertEqual(attachment.byteCount, 19)
        XCTAssertEqual(attachment.textContent, "# Brief\nSource text.")
        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(exportedFile["id"] as? String, attachmentID.uuidString)
        XCTAssertEqual((exportedFile["meta"] as? [String: Any])?["name"] as? String, "brief.md")
        XCTAssertEqual((exportedFile["meta"] as? [String: Any])?["content_type"] as? String, "text/markdown")
        XCTAssertEqual((exportedFile["data"] as? [String: Any])?["content"] as? String, "# Brief\nSource text.")
    }

    func testMarkdownExportIncludesAttachmentMetadataAndText() throws {
        let thread = ChatThread(
            title: "Attached Research",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Use this.",
                    attachments: [
                        ChatAttachment(
                            fileName: "brief.md",
                            contentType: "text/markdown",
                            byteCount: 21,
                            textContent: "# Brief\nSource notes."
                        )
                    ]
                )
            ]
        )

        let markdown = ChatExportService().markdown(for: thread)

        XCTAssertTrue(markdown.contains("Attachments:"))
        XCTAssertTrue(markdown.contains("- brief.md"))
        XCTAssertTrue(markdown.contains("# Brief"))
        XCTAssertTrue(markdown.contains("Source notes."))
    }

    func testMarkdownExportIncludesKnowledgeCitations() throws {
        let thread = ChatThread(
            title: "Cited Chat",
            messages: [
                ChatMessage(
                    role: .user,
                    content: "Use #research.",
                    citations: [
                        ChatCitation(
                            collectionName: "Research",
                            collectionSlug: "research",
                            sourceName: "fruit.txt",
                            text: "Apples are red and sweet.",
                            score: 0.98
                        )
                    ]
                )
            ]
        )

        let markdown = ChatExportService().markdown(for: thread)

        XCTAssertTrue(markdown.contains("Citations:"))
        XCTAssertTrue(markdown.contains("- #research / fruit.txt"))
        XCTAssertTrue(markdown.contains("Apples are red and sweet."))
    }

    func testLegacyChatThreadJSONDefaultsMissingUserIDToLocalUser() throws {
        let data = Data(
            """
            {
              "id": "00000000-0000-0000-0000-0000000000bb",
              "title": "Legacy chat",
              "createdAt": "2024-01-01T00:00:00Z",
              "updatedAt": "2024-01-01T00:00:00Z",
              "modelIDs": [],
              "tags": [],
              "isPinned": false,
              "isArchived": false,
              "messages": []
            }
            """.utf8
        )

        let thread = try JSONDecoder.openWebUIDecoder.decode(ChatThread.self, from: data)

        XCTAssertEqual(thread.userID, "local-user")
    }
}
