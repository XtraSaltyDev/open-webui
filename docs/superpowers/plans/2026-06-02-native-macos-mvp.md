# Native macOS MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the first native macOS Open WebUI MVP with Ollama model listing, streaming chat, settings, and persistence.

**Architecture:** Add a separate SwiftPM macOS GUI executable under `Sources/OpenWebUINative`. Keep UI, models, stores, services, and tests split by responsibility. Start with local JSON persistence for the MVP, then migrate to SwiftData or SQLite when the larger schema is ready.

**Tech Stack:** SwiftUI, Foundation, async/await, URLSession streaming, SwiftPM, XCTest.

---

## File Structure

- Create `Package.swift`: SwiftPM package definition for the app and tests.
- Create `Sources/OpenWebUINative/App/OpenWebUINativeApp.swift`: app entry point and settings scene.
- Create `Sources/OpenWebUINative/Models/ChatModels.swift`: chat, message, provider, and settings value types.
- Create `Sources/OpenWebUINative/Services/OllamaClient.swift`: Ollama status, model listing, and streaming chat.
- Create `Sources/OpenWebUINative/Services/JSONStorageService.swift`: local chat persistence.
- Create `Sources/OpenWebUINative/Services/SettingsStore.swift`: local settings persistence.
- Create `Sources/OpenWebUINative/Stores/AppStore.swift`: root app state and chat flow.
- Create `Sources/OpenWebUINative/Views/ContentView.swift`: split-view root.
- Create `Sources/OpenWebUINative/Views/SidebarView.swift`: chat history.
- Create `Sources/OpenWebUINative/Views/ChatThreadView.swift`: messages and empty state.
- Create `Sources/OpenWebUINative/Views/ComposerView.swift`: prompt entry.
- Create `Sources/OpenWebUINative/Views/ModelPickerView.swift`: model menu and refresh button.
- Create `Sources/OpenWebUINative/Views/SettingsView.swift`: Ollama base URL settings.
- Create `Tests/OpenWebUINativeTests/OllamaClientTests.swift`: test endpoint construction, decoding, and streaming line parsing.
- Create `Tests/OpenWebUINativeTests/StorageServiceTests.swift`: test persistence round trip.
- Create `script/build_and_run.sh`: repeatable build/run launcher.
- Create `.codex/environments/environment.toml`: Codex Run action.

## Task 1: Tests And Package Skeleton

**Files:**
- Create: `Package.swift`
- Create: `Tests/OpenWebUINativeTests/OllamaClientTests.swift`
- Create: `Tests/OpenWebUINativeTests/StorageServiceTests.swift`

- [x] **Step 1: Write failing Ollama and storage tests**

Tests should assert:
- `OllamaClient.listModels()` calls `/api/tags` and decodes model names.
- `OllamaClient.streamChat()` posts to `/api/chat`, sends `stream: true`, and yields content deltas from JSON lines.
- `JSONStorageService` saves and reloads a chat thread.

- [x] **Step 2: Run tests to verify they fail**

Run: `swift test`

Expected: FAIL because the app module, client, models, and storage service are not implemented yet.

## Task 2: Models And Services

**Files:**
- Create: `Sources/OpenWebUINative/Models/ChatModels.swift`
- Create: `Sources/OpenWebUINative/Services/OllamaClient.swift`
- Create: `Sources/OpenWebUINative/Services/JSONStorageService.swift`
- Create: `Sources/OpenWebUINative/Services/SettingsStore.swift`

- [ ] **Step 1: Implement Codable models**

Define `ProviderKind`, `ProviderModel`, `ProviderStatus`, `ChatRole`, `ChatMessage`, `ChatThread`, `ProviderChatMessage`, and `AppSettings`.

- [ ] **Step 2: Implement Ollama client**

Use injectable async closures for testability, and URLSession-backed defaults for real network calls.

- [ ] **Step 3: Implement JSON storage**

Persist each chat thread as `<uuid>.json` in an app support directory, sorted by `updatedAt` descending on load.

- [ ] **Step 4: Run tests**

Run: `swift test`

Expected: PASS for Ollama and storage tests.

## Task 3: Native SwiftUI MVP UI

**Files:**
- Create: `Sources/OpenWebUINative/App/OpenWebUINativeApp.swift`
- Create: `Sources/OpenWebUINative/Stores/AppStore.swift`
- Create: `Sources/OpenWebUINative/Views/ContentView.swift`
- Create: `Sources/OpenWebUINative/Views/SidebarView.swift`
- Create: `Sources/OpenWebUINative/Views/ChatThreadView.swift`
- Create: `Sources/OpenWebUINative/Views/ComposerView.swift`
- Create: `Sources/OpenWebUINative/Views/ModelPickerView.swift`
- Create: `Sources/OpenWebUINative/Views/SettingsView.swift`

- [ ] **Step 1: Build app entry and root store**

Create a `WindowGroup` and `Settings` scene with one shared `AppStore`.

- [ ] **Step 2: Build sidebar-detail-composer layout**

Use `NavigationSplitView` for native macOS sidebar behavior.

- [ ] **Step 3: Wire model refresh and streaming send**

Refresh Ollama models from the toolbar, stream deltas into the current assistant message, and persist after changes.

- [ ] **Step 4: Run build**

Run: `swift build`

Expected: PASS.

## Task 4: Build/Run Script

**Files:**
- Create: `script/build_and_run.sh`
- Create: `.codex/environments/environment.toml`

- [ ] **Step 1: Add SwiftPM GUI app launcher**

Stage `dist/OpenWebUINative.app` and launch it with `/usr/bin/open -n`.

- [ ] **Step 2: Add Codex Run action**

Point the Run action to `./script/build_and_run.sh`.

- [ ] **Step 3: Verify launch**

Run: `./script/build_and_run.sh --verify`

Expected: PASS with `OpenWebUINative` process running.
