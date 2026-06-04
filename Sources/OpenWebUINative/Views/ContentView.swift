import SwiftUI

struct ContentView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(store: store)
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
                VStack(spacing: 0) {
                    ModelPickerView(store: store)
                        .padding(.horizontal)
                        .padding(.vertical, 10)

                    Divider()

                    ChatThreadView(store: store)

                    Divider()

                    ComposerView(store: store)
                        .padding()
                }
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
    }
}
