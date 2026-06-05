import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        ViewThatFits(in: .horizontal) {
            toolbar(showLabels: true, showStatusText: true)
            toolbar(showLabels: false, showStatusText: false)
        }
        .controlSize(.small)
    }

    private func toolbar(showLabels: Bool, showStatusText: Bool) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                if showLabels {
                    Text("Provider")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                providerPicker
            }
            .layoutPriority(2)

            HStack(spacing: 5) {
                if showLabels {
                    Text("Model")
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                }
                modelPicker
            }
            .layoutPriority(2)

            if store.activeProvider.kind == .ollama, !store.ollamaRuntimeStatus.isReachable {
                Button {
                    Task {
                        await store.startOllama()
                    }
                } label: {
                    Label("Start Ollama", systemImage: "play.fill")
                }
                .labelStyle(.iconOnly)
                .help("Start Ollama")
                .disabled(store.isStartingOllama)
            }

            multiModelMenu

            Button {
                Task {
                    await store.refreshModels()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }
            .labelStyle(.iconOnly)
            .help("Refresh models")

            if store.canManageOllamaModels {
                Divider()
                    .frame(height: 20)

                TextField("Pull model", text: $store.newOllamaModelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)

                Button {
                    Task {
                        await store.pullOllamaModel()
                    }
                } label: {
                    Label("Pull", systemImage: "square.and.arrow.down")
                }
                .labelStyle(.iconOnly)
                .help("Pull Ollama model")
                .disabled(store.isPullingModel || store.newOllamaModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    Task {
                        await store.deleteSelectedOllamaModel()
                    }
                } label: {
                    Label("Delete Model", systemImage: "trash")
                }
                .labelStyle(.iconOnly)
                .help("Delete selected Ollama model")
                .disabled(store.isDeletingModel || !store.canDeleteSelectedOllamaModel)

                if store.isPullingModel {
                    ProgressView()
                        .controlSize(.small)
                }

                if let modelPullStatus = store.modelPullStatus {
                    Text(modelPullStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 160, alignment: .leading)
                }
            }

            if let modelEmptyStateMessage = store.modelEmptyStateMessage {
                Text(modelEmptyStateMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .frame(maxWidth: 240, alignment: .leading)
            }

            Spacer(minLength: 12)

            providerStatusView(showText: showStatusText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var providerPicker: some View {
        Picker("Provider", selection: Binding(
            get: { store.settings.activeProviderID },
            set: { providerID in
                Task {
                    await store.selectProvider(providerID)
                }
            }
        )) {
            ForEach(store.settings.providers.filter(\.isEnabled)) { provider in
                Text(provider.name).tag(provider.id)
            }
        }
        .labelsHidden()
        .frame(width: 118)
    }

    private var modelPicker: some View {
        Picker("Model", selection: Binding(
            get: { store.selectedModelID ?? "" },
            set: { modelID in
                Task {
                    await store.selectModel(modelID.isEmpty ? nil : modelID)
                }
            }
        )) {
            if store.models.isEmpty {
                Text("No models").tag("")
            }
            ForEach(store.models) { model in
                Text(model.name).tag(model.id)
            }
        }
        .labelsHidden()
        .frame(width: 170)
    }

    private var multiModelMenu: some View {
        Menu {
            if store.models.isEmpty {
                Text("No models")
            } else {
                ForEach(store.models) { model in
                    Button {
                        Task {
                            await store.setModel(model.id, selected: !store.selectedModelIDs.contains(model.id))
                        }
                    } label: {
                        Label(model.name, systemImage: store.selectedModelIDs.contains(model.id) ? "checkmark.circle.fill" : "circle")
                    }
                }
            }
        } label: {
            Label("\(store.selectedModelIDs.count) selected", systemImage: "square.stack.3d.up")
        }
        .labelStyle(.iconOnly)
        .help("\(store.selectedModelIDs.count) selected model\(store.selectedModelIDs.count == 1 ? "" : "s")")
        .disabled(store.models.isEmpty)
    }

    @ViewBuilder
    private func providerStatusView(showText: Bool) -> some View {
        if showText {
            Label(statusSummaryText, systemImage: statusSystemImage)
                .font(.caption)
                .foregroundStyle(statusStyle)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .frame(width: 96, alignment: .trailing)
                .help(store.providerStatus.label)
        } else {
            Image(systemName: statusSystemImage)
                .font(.caption)
                .foregroundStyle(statusStyle)
                .frame(width: 18)
                .help(store.providerStatus.label)
        }
    }

    private var statusSummaryText: String {
        switch store.providerStatus {
        case .available:
            return "Connected"
        case .unavailable:
            return "Offline"
        case .checking:
            return "Checking"
        case .unknown:
            return "Unknown"
        }
    }

    private var statusSystemImage: String {
        switch store.providerStatus {
        case .available:
            return "checkmark.circle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        case .checking:
            return "clock"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private var statusStyle: AnyShapeStyle {
        switch store.providerStatus {
        case .available:
            return AnyShapeStyle(.green)
        case .unavailable:
            return AnyShapeStyle(.red)
        case .checking:
            return AnyShapeStyle(.secondary)
        case .unknown:
            return AnyShapeStyle(.secondary)
        }
    }
}
