import SwiftUI

struct ModelPickerView: View {
    @ObservedObject var store: AppStore

    var body: some View {
        HStack(spacing: 12) {
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
            .frame(maxWidth: 220)

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
            .frame(maxWidth: 320)

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
            .disabled(store.models.isEmpty)

            Button {
                Task {
                    await store.refreshModels()
                }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            if store.canManageOllamaModels {
                Divider()
                    .frame(height: 20)

                TextField("Pull model", text: $store.newOllamaModelName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 180)

                Button {
                    Task {
                        await store.pullOllamaModel()
                    }
                } label: {
                    Label("Pull", systemImage: "square.and.arrow.down")
                }
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

            Spacer()

            Text(store.providerStatus.label)
                .font(.caption)
                .foregroundStyle(statusStyle)
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
