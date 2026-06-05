import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
                .navigationSplitViewColumnWidth(min: 300, ideal: 300, max: 300)
        } detail: {
            if let detail = store.selectedKnowledgeDocumentDetail {
                KnowledgeDocumentDetailView(detail: detail, focusedChunkID: store.selectedKnowledgeChunkID)
            } else if let channel = store.selectedChannel {
                ChannelDetailView(store: store, channel: channel)
            } else if store.isShowingEvaluationDashboard {
                EvaluationDashboardView(store: store)
            } else if store.isShowingAnalyticsDashboard {
                AnalyticsDashboardView(store: store)
            } else if store.isShowingPlayground {
                PlaygroundView(store: store)
            } else if store.isShowingFiles {
                FileLibraryView(store: store)
            } else if store.isShowingImageGeneration {
                ImageGenerationView(store: store)
            } else if store.isShowingAudio {
                AudioView(store: store)
            } else if store.isShowingCodeInterpreter {
                CodeInterpreterView(store: store)
            } else if store.isShowingTerminalSessions {
                TerminalSessionView(store: store)
            } else if store.isShowingCalendar {
                CalendarDashboardView(store: store)
            } else {
                GeometryReader { geometry in
                    VStack(spacing: 0) {
                        ModelPickerView(store: store)
                            .padding(.horizontal)
                            .padding(.vertical, 10)

                        Divider()

                        ChatThreadView(store: store, availableWidth: geometry.size.width)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)

                        Divider()

                        ComposerView(store: store)
                            .padding()
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 620)
        .alert("Provider Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .safeAreaInset(edge: .top) {
            if let recoveryNotice = store.recoveryNotice {
                RecoveryNoticeBanner(message: recoveryNotice) {
                    store.recoveryNotice = nil
                }
            }
        }
        .sheet(isPresented: Binding(
            get: { !store.settings.hasCompletedFirstRunSetup },
            set: { isPresented in
                if !isPresented {
                    Task {
                        await store.skipFirstRunSetup()
                    }
                }
            }
        )) {
            FirstRunSetupView(store: store)
                .frame(width: 560, height: 620)
        }
    }
}

private struct RecoveryNoticeBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.shield")
                .foregroundStyle(.green)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .help("Dismiss recovery notice")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }
}
