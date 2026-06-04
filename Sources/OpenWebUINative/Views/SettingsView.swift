import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @State private var ollamaBaseURL: String = ""
    @State private var openAIProviderName: String = "OpenAI"
    @State private var openAIBaseURL: String = "https://api.openai.com/v1"
    @State private var openAIAPIKey: String = ""
    @State private var makeOpenAIActive: Bool = true
    @State private var webSearchEngine: WebSearchEngine = .duckDuckGoHTML
    @State private var webSearchResultCount: Int = 3
    @State private var searxngBaseURL: String = ""
    @State private var braveSearchAPIKey: String = ""
    @State private var tavilySearchAPIKey: String = ""
    @State private var webSearchDomainFilters: String = ""
    @State private var isWebPageContentLoadingEnabled = false
    @State private var maxWebPageContentCharacters = 4_000
    @State private var isShellExecutionAllowed = true
    @State private var isPythonExecutionAllowed = true
    @State private var codeExecutionAllowedRoots = ""
    @State private var codeExecutionAllowedExecutables = ""
    @State private var codeExecutionDeniedExecutables = ""
    @State private var codeExecutionMaxTimeoutSeconds = 30
    @State private var isShowingRemoveProviderConfirmation = false

    var body: some View {
        Form {
            Section("Active Provider") {
                Picker("Provider", selection: Binding(
                    get: { store.settings.activeProviderID },
                    set: { providerID in
                        Task {
                            await store.selectProvider(providerID)
                        }
                    }
                )) {
                    ForEach(SettingsProviderPickerOption.options(for: store.settings)) { option in
                        VStack(alignment: .leading) {
                            Text(option.name)
                            Text(option.detailText)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(option.id)
                    }
                }

                Picker("Embedding model", selection: Binding<String?>(
                    get: { store.settings.embeddingModelID },
                    set: { modelID in
                        Task {
                            await store.selectEmbeddingModel(modelID)
                        }
                    }
                )) {
                    Text("Use chat model").tag(Optional<String>.none)
                    ForEach(store.embeddingModelCandidates) { model in
                        Text(model.name).tag(Optional(model.id))
                    }
                }

                Text(embeddingModelHelpText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button("Check Health") {
                        Task {
                            await store.checkActiveProviderHealth()
                        }
                    }
                    .disabled(providerHealthPresentation.isActionInProgress)

                    Label(providerHealthPresentation.label, systemImage: providerHealthPresentation.systemImage)
                        .font(.caption)
                        .foregroundStyle(providerHealthColor(for: providerHealthPresentation.tone))
                        .help(providerHealthPresentation.helpText)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Native capabilities")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), alignment: .leading)], alignment: .leading, spacing: 6) {
                        ForEach(ProviderCapabilitySummary.rows(for: store.activeProviderCapabilities)) { row in
                            Label(row.label, systemImage: row.isSupported ? "checkmark.circle.fill" : "xmark.circle")
                                .font(.caption)
                                .foregroundStyle(row.isSupported ? Color.secondary : Color.secondary.opacity(0.65))
                                .help("\(row.label): \(row.statusText)")
                        }
                    }
                }
            }

            Section("Ollama") {
                TextField("Base URL", text: $ollamaBaseURL)
                    .textFieldStyle(.roundedBorder)

                if let message = SettingsOllamaProviderFormPresentation.baseURLValidationMessage(for: ollamaBaseURL) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Save And Refresh") {
                    Task {
                        await store.updateOllamaBaseURL(ollamaBaseURL)
                    }
                }
                .disabled(!SettingsOllamaProviderFormPresentation.isSaveEnabled(baseURL: ollamaBaseURL))
            }

            Section("OpenAI-Compatible API") {
                TextField("Name", text: $openAIProviderName)
                    .textFieldStyle(.roundedBorder)

                TextField("Base URL", text: $openAIBaseURL)
                    .textFieldStyle(.roundedBorder)

                if let message = SettingsOpenAIProviderFormPresentation.baseURLValidationMessage(for: openAIBaseURL) {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                SecureField("API Key", text: $openAIAPIKey)
                    .textFieldStyle(.roundedBorder)

                Toggle("Make active after saving", isOn: $makeOpenAIActive)

                HStack {
                    Button("Save Provider") {
                        Task {
                            await store.saveOpenAICompatibleProvider(
                                name: openAIProviderName,
                                baseURL: openAIBaseURL,
                                apiKey: openAIAPIKey,
                                makeActive: makeOpenAIActive
                            )
                            openAIAPIKey = ""
                        }
                    }
                    .disabled(!SettingsOpenAIProviderFormPresentation.isSaveEnabled(baseURL: openAIBaseURL))

                    Text(SettingsOpenAIProviderFormPresentation.presentation(for: store.openAICompatibleProvider).apiKeyHelpText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if store.openAICompatibleProvider != nil {
                    Button("Remove Provider", role: .destructive) {
                        isShowingRemoveProviderConfirmation = true
                    }
                    .help("Remove the OpenAI-compatible provider and delete its Keychain API key")
                }
            }

            Section("OpenAI Account Access") {
                LabeledContent("API model access") {
                    Text(store.openAIAccountAccessPolicy.supportedAuthenticationMode.rawValue)
                }

                LabeledContent("ChatGPT subscription") {
                    Text(store.openAIAccountAccessPolicy.subscriptionAccessStatus.rawValue)
                        .foregroundStyle(.secondary)
                }

                Text("ChatGPT subscriptions and OpenAI API billing are separate. Use an OpenAI-compatible API provider with an API key stored in Keychain.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                LabeledContent("Official check") {
                    Text(store.openAIAccountAccessPolicy.lastOfficialReviewDate)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Official references")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(store.openAIAccountAccessPolicy.officialReferences) { reference in
                        Link(destination: reference.url) {
                            Label(reference.title, systemImage: "link")
                                .font(.caption)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.openAIAccountAccessPolicy.guardrails, id: \.self) { guardrail in
                        Label(guardrail.label, systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Workspace Backup") {
                HStack {
                    Button("Export Workspace") {
                        store.exportWorkspaceBackupJSONWithSavePanel()
                    }

                    Button("Import Workspace") {
                        store.importWorkspaceBackupJSONWithOpenPanel()
                    }
                }

                Text("Exports chats, folders, files, knowledge, workspace libraries, admin records, settings, calendar, channels, automations, notes, feedback, analytics source data, and playground history. Keychain secret values are not exported.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Web Search") {
                Picker("Engine", selection: $webSearchEngine) {
                    ForEach(WebSearchEngine.allCases, id: \.self) { engine in
                        Text(engine.label).tag(engine)
                    }
                }

                Stepper("Results: \(webSearchResultCount)", value: $webSearchResultCount, in: WebSearchSettings.resultCountRange)

                if webSearchEngine == .searxng {
                    TextField("SearXNG base URL", text: $searxngBaseURL)
                        .textFieldStyle(.roundedBorder)
                }

                if webSearchEngine == .brave {
                    SecureField("Brave API key", text: $braveSearchAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Text(store.settings.webSearch.braveAPIKeySecretID == nil ? "Add a Brave Search API key to use this engine." : "Leave blank to keep the stored Brave Search API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if webSearchEngine == .tavily {
                    SecureField("Tavily API key", text: $tavilySearchAPIKey)
                        .textFieldStyle(.roundedBorder)

                    Text(store.settings.webSearch.tavilyAPIKeySecretID == nil ? "Add a Tavily API key to use this engine." : "Leave blank to keep the stored Tavily API key.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                TextField("Domain filters", text: $webSearchDomainFilters)
                    .textFieldStyle(.roundedBorder)

                Toggle("Load page content", isOn: $isWebPageContentLoadingEnabled)

                Stepper("Page text: \(maxWebPageContentCharacters) characters", value: $maxWebPageContentCharacters, in: 500...WebSearchSettings.pageContentCharacterRange.upperBound, step: 500)
                    .disabled(!isWebPageContentLoadingEnabled)

                HStack {
                    Button("Save Web Search") {
                        Task {
                            await store.updateWebSearchSettings(
                                WebSearchSettings(
                                    engine: webSearchEngine,
                                    resultCount: webSearchResultCount,
                                    searxngBaseURL: searxngBaseURL,
                                    braveAPIKeySecretID: store.settings.webSearch.braveAPIKeySecretID,
                                    tavilyAPIKeySecretID: store.settings.webSearch.tavilyAPIKeySecretID,
                                    domainFilterList: webSearchDomainFilters
                                        .split(separator: ",")
                                        .map { String($0) },
                                    isPageContentLoadingEnabled: isWebPageContentLoadingEnabled,
                                    maxPageContentCharacters: maxWebPageContentCharacters
                                ),
                                braveAPIKey: braveSearchAPIKey,
                                tavilyAPIKey: tavilySearchAPIKey
                            )
                            braveSearchAPIKey = ""
                            tavilySearchAPIKey = ""
                            syncLocalFields()
                        }
                    }

                    Text("Use the globe button in chat to attach web results to the next prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Code Execution Policy") {
                Toggle("Allow shell", isOn: $isShellExecutionAllowed)
                Toggle("Allow Python", isOn: $isPythonExecutionAllowed)

                TextField("Allowed directory roots", text: $codeExecutionAllowedRoots)
                    .textFieldStyle(.roundedBorder)

                TextField("Allowed executables", text: $codeExecutionAllowedExecutables)
                    .textFieldStyle(.roundedBorder)

                TextField("Denied executables", text: $codeExecutionDeniedExecutables)
                    .textFieldStyle(.roundedBorder)

                Stepper("Max timeout: \(codeExecutionMaxTimeoutSeconds)s", value: $codeExecutionMaxTimeoutSeconds, in: 1...120)

                HStack {
                    Button("Save Code Policy") {
                        Task {
                            await store.updateCodeExecutionSettings(
                                CodeExecutionSettings(
                                    allowedLanguages: selectedCodeExecutionLanguages,
                                    allowedWorkingDirectoryRoots: codeExecutionAllowedRoots
                                        .split(separator: ",")
                                        .map { String($0) },
                                    allowedExecutableNames: codeExecutionAllowedExecutables
                                        .split(separator: ",")
                                        .map { String($0) },
                                    deniedExecutableNames: codeExecutionDeniedExecutables
                                        .split(separator: ",")
                                        .map { String($0) },
                                    maxTimeoutSeconds: Double(codeExecutionMaxTimeoutSeconds)
                                )
                            )
                            syncLocalFields()
                        }
                    }
                    .disabled(selectedCodeExecutionLanguages.isEmpty)

                    Text("The Code Interpreter is disabled by default and preflights roots plus executable rules.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Feature Toggles") {
                ForEach(nativeFeatureToggles) { feature in
                    Toggle(feature.label, isOn: Binding(
                        get: { store.isFeatureEnabled(feature) },
                        set: { isEnabled in
                            Task {
                                await store.setFeatureToggle(feature, isEnabled: isEnabled)
                            }
                        }
                    ))
                }
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            syncLocalFields()
        }
        .onChange(of: store.settings.ollamaBaseURL) {
            syncLocalFields()
        }
        .alert("Remove Provider?", isPresented: $isShowingRemoveProviderConfirmation) {
            Button("Remove", role: .destructive) {
                Task {
                    await store.removeOpenAICompatibleProvider()
                    openAIAPIKey = ""
                    syncLocalFields()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The OpenAI-compatible provider and its Keychain API key will be removed.")
        }
    }

    private func syncLocalFields() {
        ollamaBaseURL = store.settings.ollamaBaseURL
        let openAIForm = SettingsOpenAIProviderFormPresentation.presentation(for: store.openAICompatibleProvider)
        openAIProviderName = openAIForm.name
        openAIBaseURL = openAIForm.baseURL
        openAIAPIKey = openAIForm.apiKey
        webSearchEngine = store.settings.webSearch.engine
        webSearchResultCount = store.settings.webSearch.resultCount
        searxngBaseURL = store.settings.webSearch.searxngBaseURL
        braveSearchAPIKey = ""
        tavilySearchAPIKey = ""
        webSearchDomainFilters = store.settings.webSearch.domainFilterList.joined(separator: ", ")
        isWebPageContentLoadingEnabled = store.settings.webSearch.isPageContentLoadingEnabled
        maxWebPageContentCharacters = store.settings.webSearch.maxPageContentCharacters
        isShellExecutionAllowed = store.settings.codeExecution.allowedLanguages.contains(.shell)
        isPythonExecutionAllowed = store.settings.codeExecution.allowedLanguages.contains(.python)
        codeExecutionAllowedRoots = store.settings.codeExecution.allowedWorkingDirectoryRoots.joined(separator: ", ")
        codeExecutionAllowedExecutables = store.settings.codeExecution.allowedExecutableNames.joined(separator: ", ")
        codeExecutionDeniedExecutables = store.settings.codeExecution.deniedExecutableNames.joined(separator: ", ")
        codeExecutionMaxTimeoutSeconds = Int(store.settings.codeExecution.maxTimeoutSeconds)
    }

    private var nativeFeatureToggles: [AppFeatureToggle] {
        AppFeatureToggle.allCases.filter { $0.groupLabel == "Native Surfaces" }
    }

    private var embeddingModelHelpText: String {
        if !store.canCreateEmbeddings {
            return "The active provider does not support native embeddings."
        }
        if store.embeddingModelCandidates.isEmpty {
            return "Refresh models or choose a provider with embedding support before indexing knowledge."
        }
        return "Knowledge import and retrieval prefer provider models that look embedding-specific."
    }

    private var providerHealthPresentation: SettingsProviderHealthPresentation {
        SettingsProviderHealthPresentation.presentation(for: store.providerStatus)
    }

    private func providerHealthColor(for tone: SettingsProviderHealthTone) -> Color {
        switch tone {
        case .neutral:
            return .secondary
        case .progress:
            return .blue
        case .success:
            return .green
        case .failure:
            return .red
        }
    }

    private var selectedCodeExecutionLanguages: [CodeExecutionLanguage] {
        var languages: [CodeExecutionLanguage] = []
        if isShellExecutionAllowed {
            languages.append(.shell)
        }
        if isPythonExecutionAllowed {
            languages.append(.python)
        }
        return languages
    }
}

enum SettingsProviderHealthTone: Equatable, Sendable {
    case neutral
    case progress
    case success
    case failure
}

struct SettingsProviderHealthPresentation: Equatable, Sendable {
    let label: String
    let systemImage: String
    let tone: SettingsProviderHealthTone
    let helpText: String
    let isActionInProgress: Bool

    static func presentation(for status: ProviderStatus) -> SettingsProviderHealthPresentation {
        switch status {
        case .unknown:
            return SettingsProviderHealthPresentation(
                label: "Health unknown",
                systemImage: "questionmark.circle",
                tone: .neutral,
                helpText: "Run a health check to verify the active provider before using it.",
                isActionInProgress: false
            )
        case .checking:
            return SettingsProviderHealthPresentation(
                label: "Checking provider...",
                systemImage: "arrow.triangle.2.circlepath",
                tone: .progress,
                helpText: "Contacting the active provider.",
                isActionInProgress: true
            )
        case .available(let message):
            return SettingsProviderHealthPresentation(
                label: message,
                systemImage: "checkmark.circle.fill",
                tone: .success,
                helpText: "The active provider responded successfully.",
                isActionInProgress: false
            )
        case .unavailable(let message):
            return SettingsProviderHealthPresentation(
                label: message,
                systemImage: "xmark.octagon.fill",
                tone: .failure,
                helpText: "The active provider could not be reached. Check the base URL, API key, or local runtime.",
                isActionInProgress: false
            )
        }
    }
}

struct SettingsProviderPickerOption: Identifiable, Equatable {
    let id: UUID
    let name: String
    let detailText: String
    let isActive: Bool

    static func options(for settings: AppSettings) -> [SettingsProviderPickerOption] {
        settings.providers
            .filter(\.isEnabled)
            .map { provider in
                SettingsProviderPickerOption(
                    id: provider.id,
                    name: provider.name,
                    detailText: "\(kindLabel(for: provider.kind)) - \(provider.baseURL)",
                    isActive: provider.id == settings.activeProviderID
                )
            }
    }

    private static func kindLabel(for kind: ProviderKind) -> String {
        switch kind {
        case .ollama:
            return "Ollama"
        case .openAICompatible:
            return "OpenAI-compatible"
        case .localFunction:
            return "Local function"
        }
    }
}

enum SettingsProviderBaseURLValidation {
    static func message(for baseURL: String) -> String? {
        let trimmedBaseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedBaseURL.isEmpty else {
            return "Enter a provider base URL."
        }
        guard
            let components = URLComponents(string: trimmedBaseURL),
            let scheme = components.scheme?.lowercased(),
            ["http", "https"].contains(scheme),
            components.host?.isEmpty == false
        else {
            return "Enter a valid http or https provider base URL."
        }
        return nil
    }
}

enum SettingsOllamaProviderFormPresentation {
    static func isSaveEnabled(baseURL: String) -> Bool {
        baseURLValidationMessage(for: baseURL) == nil
    }

    static func baseURLValidationMessage(for baseURL: String) -> String? {
        SettingsProviderBaseURLValidation.message(for: baseURL)
    }
}

struct SettingsOpenAIProviderFormPresentation: Equatable {
    let name: String
    let baseURL: String
    let apiKey: String
    let apiKeyHelpText: String

    static func presentation(for provider: ProviderConfiguration?) -> SettingsOpenAIProviderFormPresentation {
        SettingsOpenAIProviderFormPresentation(
            name: provider?.name ?? "OpenAI",
            baseURL: provider?.baseURL ?? "https://api.openai.com/v1",
            apiKey: "",
            apiKeyHelpText: provider == nil
                ? "Enter an API key to store it in Keychain."
                : "Leave blank to keep the existing Keychain API key."
        )
    }

    static func isSaveEnabled(baseURL: String) -> Bool {
        baseURLValidationMessage(for: baseURL) == nil
    }

    static func baseURLValidationMessage(for baseURL: String) -> String? {
        SettingsProviderBaseURLValidation.message(for: baseURL)
    }
}
