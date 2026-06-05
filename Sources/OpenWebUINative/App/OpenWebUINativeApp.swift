import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
struct OpenWebUINativeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    @State private var isShowingDeleteAllConfirmation = false

    var body: some Scene {
        WindowGroup("Open WebUI Native") {
            ContentView(store: store)
                .task {
                    await store.load()
                    store.startAutomationScheduler()
                    store.startCalendarReminderScheduler()
                }
                .onDisappear {
                    store.stopAutomationScheduler()
                    store.stopCalendarReminderScheduler()
                    Task {
                        await store.stopAppOwnedOllamaIfNeeded()
                    }
                }
                .onOpenURL { url in
                    _ = store.handleAppURL(url)
                }
                .alert("Delete All Chats?", isPresented: $isShowingDeleteAllConfirmation) {
                    Button("Delete All", role: .destructive) {
                        Task {
                            await store.deleteAllThreads()
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("All chats will be permanently deleted.")
                }
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Chat") {
                    store.createThread()
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandMenu("Chat") {
                Button("New Folder") {
                    Task {
                        await store.createFolder(named: "New Folder")
                    }
                }
                .disabled(!store.isFeatureEnabled(.folders))

                Button("Remove Chat from Folder") {
                    if let selectedThreadID = store.selectedThreadID {
                        Task {
                            await store.assignThread(selectedThreadID, toFolder: nil)
                        }
                    }
                }
                .disabled(!store.isFeatureEnabled(.folders) || store.selectedThread?.folderID == nil)

                Divider()

                Button("Copy Chat as Markdown") {
                    store.exportSelectedThreadAsMarkdownToPasteboard()
                }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(store.selectedThread == nil)

                Button("Refresh Models") {
                    Task {
                        await store.refreshModels()
                    }
                }
                .keyboardShortcut("r", modifiers: [.command])

                Button("Share Chat...") {
                    store.shareSelectedThreadAsMarkdown()
                }
                .disabled(store.selectedThread == nil)

                Button("Copy Chat Link") {
                    store.copySelectedThreadLink()
                }
                .disabled(store.selectedThread == nil)

                Button("Export Chat JSON...") {
                    store.exportSelectedThreadJSONWithSavePanel()
                }
                .disabled(store.selectedThread == nil)

                Button("Export Chat for Open WebUI...") {
                    store.exportSelectedThreadOpenWebUIJSONWithSavePanel()
                }
                .disabled(store.selectedThread == nil)

                Button("Export All Chats JSON...") {
                    store.exportAllThreadsJSONWithSavePanel()
                }
                .disabled(store.threads.isEmpty)

                Button("Export All Chats for Open WebUI...") {
                    store.exportAllThreadsOpenWebUIJSONWithSavePanel()
                }
                .disabled(store.threads.isEmpty)

                Button("Import Chat JSON...") {
                    store.importChatThreadJSONWithOpenPanel()
                }

                Button("Import Chats JSON...") {
                    store.importChatThreadsJSONWithOpenPanel()
                }

                Divider()

                Button("Delete All Chats...") {
                    isShowingDeleteAllConfirmation = true
                }
                .disabled(store.threads.isEmpty)
            }
        }

        Settings {
            SettingsView(store: store)
                .frame(width: 480)
        }
    }
}
