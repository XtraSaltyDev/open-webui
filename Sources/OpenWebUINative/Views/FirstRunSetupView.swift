import SwiftUI

struct FirstRunSetupView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var providerKind: ProviderKind = .ollama
    @State private var ollamaBaseURL = "http://localhost:11434"
    @State private var openAIProviderName = "OpenAI"
    @State private var openAIBaseURL = "https://api.openai.com/v1"
    @State private var openAIAPIKey = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Up OpenWebUINative")
                .font(.title2.weight(.semibold))

            Form {
                Section("Provider") {
                    Picker("Provider", selection: $providerKind) {
                        Text("Ollama").tag(ProviderKind.ollama)
                        Text("OpenAI-compatible").tag(ProviderKind.openAICompatible)
                    }
                    .pickerStyle(.segmented)

                    if providerKind == .ollama {
                        TextField("Base URL", text: $ollamaBaseURL)
                            .textFieldStyle(.roundedBorder)
                        LabeledContent("Runtime") {
                            Text(store.ollamaRuntimeStatus.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                        HStack {
                            Button("Start Ollama") {
                                Task {
                                    await store.startOllama()
                                }
                            }
                            .disabled(store.isStartingOllama)

                            Button("Recheck") {
                                Task {
                                    await store.refreshOllamaRuntimeStatus()
                                    if store.ollamaRuntimeStatus.isReachable {
                                        await store.refreshModels()
                                    }
                                }
                            }
                        }
                    } else {
                        TextField("Name", text: $openAIProviderName)
                            .textFieldStyle(.roundedBorder)
                        TextField("Base URL", text: $openAIBaseURL)
                            .textFieldStyle(.roundedBorder)
                        SecureField("API Key", text: $openAIAPIKey)
                            .textFieldStyle(.roundedBorder)
                        Text("API keys are written to Keychain only. They are not saved in workspace backups.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button("Save Provider") {
                        Task {
                            await saveProvider()
                        }
                    }
                    .disabled(!isProviderSaveEnabled)
                }

                Section("Health And Default Model") {
                    HStack {
                        Button("Check Health") {
                            Task {
                                await store.checkActiveProviderHealth()
                                await store.refreshModels()
                            }
                        }
                        Label(store.providerStatus.label, systemImage: providerHealthImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Picker("Default model", selection: Binding<String?>(
                        get: { store.settings.selectedModelID },
                        set: { modelID in
                            Task {
                                await store.selectModel(modelID)
                            }
                        }
                    )) {
                        Text("No model selected").tag(Optional<String>.none)
                        ForEach(store.models) { model in
                            Text(model.name).tag(Optional(model.id))
                        }
                    }
                    .disabled(store.models.isEmpty)

                    if providerKind == .ollama, store.models.isEmpty {
                        HStack {
                            TextField("Pull model, e.g. llama3.2", text: $store.newOllamaModelName)
                                .textFieldStyle(.roundedBorder)

                            Button("Pull") {
                                Task {
                                    await store.pullOllamaModel()
                                }
                            }
                            .disabled(store.isPullingModel || store.newOllamaModelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                Section("Local Data") {
                    LabeledContent("Data root") {
                        Text(store.appDataPaths.appDataRootPath)
                            .textSelection(.enabled)
                    }
                    LabeledContent("Local execution") {
                        Text(store.settings.localExecution.isEnabled ? "Enabled" : "Disabled by default")
                    }
                    Text("Chats, settings, and backups stay under your local Application Support data root. Local execution stays disabled until you accept the safety warning in Settings.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            HStack {
                Button("Skip Setup") {
                    Task {
                        await store.skipFirstRunSetup()
                        dismiss()
                    }
                }

                Spacer()

                Button("Finish Setup") {
                    Task {
                        await store.completeFirstRunSetup()
                        if store.settings.hasCompletedFirstRunSetup {
                            dismiss()
                        }
                    }
                }
                .disabled(!store.canCompleteFirstRunSetup)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .onAppear {
            syncFields()
        }
    }

    private var isProviderSaveEnabled: Bool {
        switch providerKind {
        case .ollama:
            return SettingsOllamaProviderFormPresentation.isSaveEnabled(baseURL: ollamaBaseURL)
        case .openAICompatible:
            return SettingsOpenAIProviderFormPresentation.isSaveEnabled(baseURL: openAIBaseURL)
        case .localFunction:
            return false
        }
    }

    private var providerHealthImage: String {
        switch store.providerStatus {
        case .available:
            return "checkmark.circle.fill"
        case .checking:
            return "arrow.triangle.2.circlepath"
        case .unavailable:
            return "xmark.octagon.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    private func saveProvider() async {
        switch providerKind {
        case .ollama:
            await store.updateOllamaBaseURL(ollamaBaseURL)
            await store.refreshOllamaRuntimeStatus()
        case .openAICompatible:
            await store.saveOpenAICompatibleProvider(
                name: openAIProviderName,
                baseURL: openAIBaseURL,
                apiKey: openAIAPIKey,
                makeActive: true
            )
            openAIAPIKey = ""
        case .localFunction:
            break
        }
    }

    private func syncFields() {
        providerKind = store.activeProvider.kind == .openAICompatible ? .openAICompatible : .ollama
        ollamaBaseURL = store.settings.ollamaBaseURL
        if let provider = store.openAICompatibleProvider {
            openAIProviderName = provider.name
            openAIBaseURL = provider.baseURL
        }
    }
}
