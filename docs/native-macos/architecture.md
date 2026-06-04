# Native macOS Architecture

## Module Shape

The native app lives in `Sources/OpenWebUINative` as a SwiftPM macOS GUI executable. It is intentionally separate from the existing Svelte/FastAPI code so the native app can build, test, and ship independently. Local packaging uses `script/build_and_run.sh --package` to produce `dist/OpenWebUINative.app` from the SwiftPM binary plus `Resources/macOS/OpenWebUINative-Info.plist`; `script/build_and_run.sh --validate-package` ad-hoc signs that bundle with hardened runtime options and verifies the local code signature.

## Layers

- `App`: SwiftUI entry point and macOS launch behavior.
- `Views`: Native UI surfaces such as sidebar, chat detail, composer, model picker, and settings.
- `Models`: Codable value types for chats, messages, providers, models, and settings.
- `Stores`: Main-actor app state that coordinates UI, services, and persistence.
- `Services`: Networking, provider adapters, storage, settings, secrets, knowledge, tools, and admin services.
- `Support`: Small helpers and shared utilities.

## First Services

- `OllamaClient`: talks to local Ollama, lists models, checks runtime health, streams chat deltas, streams raw prompt completions through `/api/generate`, pulls models, and deletes local models.
- `OpenAICompatibleClient`: talks to OpenAI-compatible `/models`, `/chat/completions`, `/completions`, `/embeddings`, `/images/generations`, `/images/edits`, `/audio/transcriptions`, and `/audio/speech` endpoints using bearer API-key auth.
- `ProviderFactory`: builds the active provider adapter from the saved provider configuration.
- `KeychainSecretStore`: stores provider API keys in macOS Keychain. Settings files store only the provider metadata and Keychain secret ID.
- `ChatExportService`: produces Markdown/native JSON chat exports, produces Open WebUI-compatible selected-chat and all-chat `{ "chats": [...] }` import envelopes, decodes native JSON chat imports, and tolerantly imports Open WebUI chat records by flattening the active `chat.history.currentId` branch from the message map.
- `ChatShareService`: presents native macOS sharing for exported Markdown chat content.
- `JSONStorageService`: MVP local persistence for chat threads.
- `JSONFolderStorageService`: local persistence for chat folders; folder create, assignment, and delete mutations are blocked when the Folders feature toggle is disabled.
- `JSONPromptStorageService`: local persistence for reusable prompt library entries, including prior prompt-version snapshots.
- `PromptExportService`: exports native prompt bundles, exports raw Open WebUI-style prompt records, and imports either native bundles or Open WebUI-style prompt records while preserving prompt version history when present.
- `JSONNoteStorageService`: local persistence for native notes.
- `JSONAutomationStorageService`: local persistence for native automation definitions.
- `JSONAutomationRunStorageService`: local persistence for manual automation run history.
- `AutomationExportService`: exports native automation bundles and raw Open WebUI automation records, and imports either native bundles, raw native automation arrays, or Open WebUI-style automation records with nested `data` payloads.
- `AutomationScheduleService`: validates and previews the starter daily/weekly RRULE subset, calculates the next local run time, and selects active past-due automations for app-open scheduler execution.
- `JSONCalendarStorageService`: local persistence for native calendar snapshots.
- `CalendarExportService`: exports native calendar bundles and raw Open WebUI calendar/event records, and imports either native snapshots, raw event arrays, or Open WebUI-style calendar/event records with reminder metadata and nanosecond timestamp conversion.
- `CalendarRecurrenceService`: expands the supported daily/weekly/monthly/yearly calendar RRULE subset into visible event occurrences while leaving unsupported rules as their original saved event.
- `CalendarMonthGridService`: builds native month grids with leading/trailing days and buckets single-day, multi-day, or expanded recurring events by day overlap.
- `CalendarWeekGridService`: builds native week grids that respect the user's first weekday and bucket single-day, multi-day, or expanded recurring events by day overlap.
- `CalendarDayScheduleService`: builds native day schedules with all-day event separation and 24 stable hour slots for timed or expanded recurring events.
- `WorkspaceBackupService`: composes the current local app state into one versioned JSON backup and decodes workspace restore files. It includes persisted local data but excludes Keychain secret values by design.
- `JSONToolStorageService`: local persistence for native workspace tool records.
- `ToolExportService`: exports native tool bundles and raw Open WebUI tool records, and imports either native bundles, raw native tool arrays, or Open WebUI-style tool records with nested specs.
- `JSONFunctionStorageService`: local persistence for native workspace function records.
- `FunctionExportService`: exports native function bundles and raw Open WebUI function records, and imports either native bundles, raw native function arrays, or Open WebUI-style function records with manifests and valves.
- `JSONSkillStorageService`: local persistence for native workspace skill records.
- `SkillExportService`: exports native skill bundles and raw Open WebUI skill records, and imports either native bundles, raw native skill arrays, or Open WebUI-style skill records with tags.
- `JSONFeedbackStorageService`: local persistence for native feedback records.
- `FeedbackExportService`: exports native feedback bundles and raw Open WebUI feedback records, and imports either native bundles, raw native feedback arrays, or Open WebUI-style feedback records with `data`, `meta`, `snapshot`, and local moderation status payloads.
- `FeedbackEvaluationService`: derives local model evaluation summaries from feedback records, including Elo-style arena scores, win/loss counts, sentiment counts, and top tags.
- `JSONAdminDirectoryStorageService`: local persistence for native users, groups, group members, and flat permission grants.
- `SettingsStore`: MVP local persistence for provider settings and feature toggles.
- `AppStore`: root UI state for selected chat, chat pinning/order, chat archive visibility, selected model, status, sending, loading, and persistence.

Future phases should move persistence to SwiftData or SQLite-backed repositories once the data model stabilizes across chat, RAG, admin, and import/export workflows.

## Attachment Path

The Phase 2 attachment path is intentionally text-first with selectable-PDF support:

- `ComposerView` opens a native SwiftUI file importer for text, source, Markdown-like files, and PDFs.
- `AppStore.importAttachment(from:)` uses the shared import reader to read UTF-8 text or extract selectable PDF text with PDFKit, records file metadata, persists a reusable local `AppFile`, and keeps a matching attachment pending until the user sends.
- `AppStore.importFileToLibrary(from:)` uses the shared file reader for Files-surface imports that should save reusable records without mutating the current chat draft; unlike composer attachments, Files-only imports can preserve binary originals even when extracted text is unavailable.
- `AppStore` blocks saved file-library import, attach/share/copy use, rename/edit/delete mutation, and Files JSON import including file/open-panel entry points when the Files feature is disabled while preserving already stored records.
- `JSONAppFileStorageService` stores reusable file-library records, extracted text when available, and original imported bytes when available under Application Support so imported files can be reattached or exported from the Files surface after restart.
- `AppStore.attachFileToChatContext(_:)` turns a saved file-library record with extracted text back into a normal pending `ChatAttachment`, reusing the same provider-context and message-persistence path as freshly imported files; binary-only records stay exportable but are blocked from text chat context until extracted text exists.
- `FileLibraryView` exposes the saved local files as a native sidebar surface with free-text search, Open WebUI-style wildcard filename search, broad file import, original-file export/share when bytes are available, extracted-text copy/export/editing/sharing, JSON import/export, Open WebUI-shaped JSON export/import, attach, rename, individual delete, and confirmed delete-all actions, and the Files feature toggle can hide the surface without deleting stored records.
- `AppStore.attachNoteToChatContext(_:)` turns a native note into a Markdown `ChatAttachment`, reusing the same pending composer strip, message persistence, provider context, and export path as file attachments.
- `ChatMessage.attachments` persists attachments with the user message.
- Provider requests include the prompt plus an explicit attached-context block so Ollama and OpenAI-compatible adapters can use the imported text.
- Markdown and JSON exports include attachment metadata and text content.

Future RAG work should extend this import path with OCR and richer document parsers, then add production vector storage, citations, and knowledge collection management polish.

## Chat Search And Links

- `AppStore.filteredThreads()` and `AppStore.filteredArchivedThreads()` share the sidebar search parser.
- Free text still searches chat title, tags, model IDs, and message text.
- Operator tokens `tag:name`, `folder:name`, `pinned:true`, `pinned:false`, `archived:true`, and `archived:false` are parsed as structured filters and removed from the free-text query.
- `ChatSearchService` powers the separate native message transcript search surface by returning matching visible-chat message snippets with thread/message IDs. Selecting a result stores the focused message ID, opens the thread, and lets `ChatThreadView` scroll to and outline the matching bubble.
- `ChatThread.deepLinkURL` creates durable app-local `openwebui-native://chats/{id}` chat links, `ChatThread.deepLinkURL(forMessageID:)` creates `openwebui-native://chats/{id}/messages/{messageID}` message links, and `AppStore.handleAppURL(_:)` routes incoming chat, message, or note links to the matching local record.
- `OpenWebUINative-Info.plist` registers the `openwebui-native` URL scheme so packaged apps can receive native links through SwiftUI `.onOpenURL`.
- `SidebarView` exposes archive-all, all-chat export, and confirmed delete-all from recent chats, plus archived chats as a native disclosure with per-chat unarchive, unarchive-all, and archived JSON export actions.

## Knowledge Path

The initial Phase 4 RAG path is text-first, local-first, and supports selectable PDFs:

- `KnowledgeCollection`, `KnowledgeDocument`, and `KnowledgeChunk` model collections, user/group collection access grants, imported files, and embedded text chunks.
- `KnowledgeTextChunker` splits imported text into chunk records with source metadata.
- `AppStore` extracts UTF-8 text or selectable PDF text, or converts an existing native note into Markdown source text, before handing imported documents to `KnowledgeService`.
- `KnowledgeService` creates/renames/deletes collections, lists collection documents, imports/reindexes/renames/deletes text documents, requests embeddings from the active provider, and retrieves similar chunks with cosine similarity.
- `KnowledgeService` also exports a full native JSON knowledge bundle or a single-collection bundle and imports either that bundle or a raw `KnowledgeSnapshot`, merging by stable IDs so local backups and shared collections can be restored without duplicating records.
- `AppStore` owns Knowledge feature-toggle blocking and `knowledge.write` admin-directory enforcement for collection creation/rename/deletion, document import/reindex/rename/delete, and knowledge JSON import before file access, provider calls, or storage mutation, and blocks single-collection sharing, document preview selection, citation-source opening, and `#collection` retrieval before provider chat when Knowledge is disabled.
- `AppStore` also filters visible collections, document previews, citation-source opening, and `#collection-slug` retrieval against local user/group collection grants.
- `JSONKnowledgeStorageService` persists the current MVP knowledge snapshot locally.
- `KnowledgeDocumentMetadata` preserves MIME hints, byte counts, source kind, imported filename, and last-indexed timestamps so document details and JSON exports can distinguish renamed documents from their original import source.
- `AppSettings.embeddingModelID` can pin knowledge import and retrieval to a dedicated embedding model. When unset, `AppStore.embeddingModelCandidates` prefers active-provider models with provider-neutral capability metadata indicating embedding support, then uses the active chat model as a last resort.
- `AppStore` resolves `#collection-slug` mentions before sending a prompt and stores retrieved chunks as `ChatCitation` values with source collection, document, and chunk IDs.
- `SidebarView` displays imported documents under each collection, supports document selection, exposes collection/document rename, collection access-grant editing, single-collection sharing, and per-document deletion, provides note-to-knowledge import actions, and provides native knowledge JSON import/export controls.
- `KnowledgeDocumentDetailView` previews the indexed chunk text and document metadata for the selected document so users can inspect the RAG source material and import details.
- `ChatThreadView` shows citations in the transcript and can open a citation's source document preview with the cited chunk highlighted; `ChatExportService` includes citations in Markdown/JSON exports.

The production version should replace or wrap the JSON snapshot with SQLite or a dedicated local vector backend, add richer document parser services and collection metadata editing beyond names, add answer-span citation mapping, and continue replacing heuristic model detection with provider-reported capabilities where providers expose that metadata.

## Message Rendering

- `MarkdownMessageParser` splits chat content into markdown text, inline/block LaTeX math, and fenced code segments.
- `MarkdownMessageRenderer` uses native `AttributedString(markdown:)` for markdown text and falls back to plain text when parsing fails.
- `CodeSyntaxHighlighter` provides lightweight native token coloring for common Swift, JavaScript/TypeScript, Python, and shell fenced code blocks while preserving the original source text exactly.
- `ChatThreadView` renders math segments as selectable native SwiftUI math text panels and code segments as monospaced panels with lightweight syntax coloring and a copy-code action.

Full KaTeX-grade math typesetting and Shiki-style syntax highlighting remain planned; they should use dedicated renderers rather than ad hoc substitutions.

## Message Actions

- `ChatThreadView` exposes visible and context-menu actions for copy, edit, regenerate, rating, and feedback.
- `AppStore.regenerateResponse` preflights the active provider's chat capability before clearing the existing assistant content or opening a stream, so unsupported providers leave the old answer intact and show a clear local error.

## Multi-Model Chat

- `AppSettings.selectedModelIDs` stores the selected model list while `selectedModelID` remains the primary/backward-compatible model.
- `ModelPickerView` keeps the primary model picker and adds a multi-select model menu.
- `AppStore.send(_:)` creates one user message and one assistant message per selected model.
- Each assistant branch streams with its own model ID and excludes sibling assistant branches from provider context, so model outputs stay comparable.
- Branch failures are isolated to the matching assistant message, allowing later model branches to continue and finish.
- Selected model branches run concurrently through cancellable branch tasks, while SwiftUI state updates remain routed through `AppStore`.
- `AppStore.streamingAssistantBranchCount` and `chatGenerationProgressText` summarize the selected thread's active assistant branches so the composer can show how many responses are still generating.
- `ComposerView` exposes active-branch progress text plus a stop action while sending; `AppStore.cancelCurrentSend()` cooperatively ends active branches and finalizes assistant messages.
- Streaming assistant bubbles expose per-branch stop actions; `AppStore.cancelAssistantBranch(messageID:)` cooperatively finalizes only that assistant message while sibling model branches continue streaming.
- `ChatGenerationMetrics` records assistant branch start/completion timestamps, persists with chat JSON, and gives `ChatThreadView` a compact elapsed-time label for completed assistant responses.
- `ChatTokenUsage` normalizes provider-reported prompt/completion/total token counts from Ollama and OpenAI-compatible streams, persists them on assistant messages, and feeds local analytics.
- Ollama and OpenAI-compatible chat stream wrappers cancel their worker tasks when the app stops consuming a stream, so stopped responses can tear down underlying line readers instead of waiting for later provider output.

Future work should add deeper performance instrumentation for large model selections.

## Prompt Library

- `SavedPrompt` stores reusable prompt title, slash command, tags/categories, user/group access grants, content, and timestamps.
- `JSONPromptStorageService` persists prompt records as local JSON files for the MVP.
- `PromptVariableResolver` extracts `{{variable}}` placeholders, preserves first-seen variable order, replaces all occurrences with user-provided values, and reports missing values clearly.
- `AppStore` owns prompt create, update, delete, slash-command lookup, variable-aware insert actions, disabled-feature blocking for prompt writes/imports/file and open-panel import entry points/insertions/command lookup/sharing, `prompts.write` admin-directory enforcement for write operations, and prompt-variable lookup so the sidebar UI does not know about storage details.
- `AppStore` also owns prompt JSON import/export, Open WebUI prompt-record export, count-only prompt import/export audit events, and single-prompt share actions, routing those portable payloads through `PromptExportService` only after the Prompts feature check passes. Prompt updates append the previous prompt state into `SavedPrompt.versions` before the edited record is saved.
- `PromptLibraryView` exposes native sidebar rows with command/tag metadata, permission-aware management controls, a create/edit sheet with command, tag, and access-grant editing, context menus, variable-value collection before insertion, composer insertion, single-prompt sharing, and native/Open WebUI export options.
- Composer send actions expand matching saved prompt commands, such as `/triage`, into the draft instead of sending the command text. Commands for prompts with required `{{variables}}` show a clear error and should be inserted from the prompt library so values can be collected.
- Prompt import/export preserves Open WebUI-style `tags` as native prompt categories and `access_grants` as native user/group grant IDs, with trimming, empty-value removal, and duplicate collapse.

Future work should add broader admin prompt management.

## Tool Library

- `AppTool` stores local workspace tool ID, name, Python/source content, optional description, Open WebUI-style specs, manifest metadata, and timestamps.
- `JSONValue` preserves arbitrary nested JSON so Open WebUI tool `specs` and manifests can round-trip without flattening unknown fields.
- `JSONToolStorageService` persists tool records as local JSON files for the MVP.
- `ToolExportService` exports native tool bundles and raw Open WebUI tool records, and imports native bundles, raw native arrays, or Open WebUI-style tool records.
- `LocalToolExecutionService` runs Open WebUI-style Python `Tools` class methods by passing JSON-object arguments to `/usr/bin/python3`, injects configured tool valves, reads `Valves` JSON schemas for native valves editing, captures stdout/stderr/exit code, and returns an `AppToolRun` after `AppStore` enforces the Tools feature toggle.
- `JSONToolRunStorageService` persists local tool run history so test-run results can be audited and included in workspace backups.
- `AppStore` owns tool create, update, delete, JSON-object valves validation/editing, schema-derived valves JSON defaults, schema field metadata, save-time schema validation, disabled-feature blocking for tool create/update/delete/import/share plus local tool execution and valves-schema Python calls, `tools.write` admin-directory enforcement for write operations, `tools.execute` enforcement for local tool runs, native/Open WebUI JSON export, JSON import actions, single-tool JSON sharing, persisted run history, and local audit events so the sidebar UI does not know about persistence details.
- `ToolLibraryView` exposes native sidebar rows, permission-aware management controls, a create/edit sheet with monospaced source editing, schema-default valves JSON generation, generated primitive valves field controls bound back to the raw JSON body, valves JSON editing, context-menu actions, import/export buttons, a local tool run sheet, and recent run previews.
- `AppToolServer` stores direct tool-server registry entries for stdio command servers and HTTP MCP-style endpoints, including arguments, environment variables, enabled state, and timestamps.
- `JSONToolServerStorageService` persists tool-server records as local JSON files.
- `ToolServerExportService` exports native tool-server bundles and imports native bundles, raw native arrays, or Open WebUI-shaped records with `type`, `command`, `args`, `env`, `url`, and `enabled` fields.
- `ToolServerCheckService` performs lightweight reachability checks: stdio records validate that the command can be resolved on disk or in `PATH`, and HTTP records validate that the endpoint returns a normal HTTP response.
- `ToolServerMCPDiscoveryService` performs HTTP MCP discovery and stdio subprocess MCP discovery by sending JSON-RPC `initialize`, `notifications/initialized`, and `tools/list` messages with bounded stdio response timeouts, then surfaces discovered tool names, titles, descriptions, and input schemas as transient `AppToolServerTool` records. It also supports basic HTTP and stdio MCP `tools/call` invocation with JSON-object arguments, behind Direct Tool Servers feature-toggle and `tools.execute` enforcement in `AppStore`, and stores the returned content as local `AppToolServerRun` history.
- `ToolArgumentTemplateService` converts discovered MCP input schemas and local valves schemas into editable JSON-object templates, extracts field metadata for native controls, updates field values inside raw JSON-object bodies, and validates required fields, JSON types including nullable/union type arrays, `const` exact values, `anyOf`/`oneOf`/`allOf` composition, nested object fields, array item types, enums, string length, regex patterns, numeric bounds, numeric multiples, unique array items, and disallowed extra object properties before known MCP tool calls or valves saves are accepted.
- `ToolServerInvocationService` posts raw JSON payloads to HTTP tool-server endpoints and runs raw stdio tool-server commands after `AppStore` enforces the Direct Tool Servers feature toggle and `tools.execute`, capturing HTTP response bodies/status codes or stdio stdout/stderr/exit codes as `AppToolServerRun` records. Stdio invocation has bounded lifecycle handling for timeout and task cancellation so hanging subprocesses terminate with clear failed runs. `AppStore.toolServerInvocationRequestBody` holds the native direct-invocation JSON draft when no explicit request body is passed. MCP stdio tool calls route through `ToolServerMCPDiscoveryService`.
- `JSONToolServerRunStorageService` persists tool-server invocation history locally so run results can be audited, deleted with content-free audit markers, and included in workspace backups.
- `ToolServerLibraryView` exposes an opt-in native sidebar registry surface behind the Direct Tool Servers feature toggle, including permission-aware registry management controls, an editable direct-invocation JSON payload, `tools.execute`-aware invocation controls, `tools.write`-aware run-history deletion, and a native JSON argument editor sheet for discovered MCP tools.

Future work should add Python execution isolation, tool-call routing into provider requests, nested/generated advanced JSON Schema forms, MCP SSE/session hardening, richer long-running stdio session controls, and richer audit logs.

## Function Library

- `AppFunction` stores local workspace function ID, name, filter/action/pipe type, Python/source content, optional description, manifest metadata, valves, active/global flags, and timestamps.
- `AppFunctionKind` maps Open WebUI function `type` strings into native Swift cases: `filter`, `action`, and `pipe`.
- `JSONFunctionStorageService` persists function records as local JSON files for the MVP.
- `AppFunctionRun` stores local test-run history for a function, including function ID/name/type, method name, JSON input body, stdout, stderr, status, exit code, errors, and timestamps.
- `JSONFunctionRunStorageService` persists function test-run records as local JSON files.
- `LocalFunctionExecutionService` runs a selected Python function method through `/usr/bin/python3`, passes JSON input as keyword arguments, captures stdout/stderr, records failures/timeouts, supports the native run sheet, reads `Valves` JSON schemas for native valves editing, powers active chat filter routing, discovers active manifold pipe submodels through `pipes()`, backs active pipe functions that appear as local chat models, and executes active action functions from assistant-message action menus after `AppStore` enforces the Functions feature toggle.
- `FunctionExportService` exports native function bundles and raw Open WebUI function records, and imports native bundles, raw native arrays, or Open WebUI-style function records.
- `AppStore` owns function create, update, delete, JSON-object valves validation/editing, schema-derived valves JSON defaults, schema field metadata, save-time schema validation, disabled-feature blocking for function create/update/delete/import/share plus local function execution, valves-schema Python calls, action affordances, and pipe model surfacing, local test-runs, active `filter` `inlet`/`outlet` routing around provider chat streams, active single and manifold `pipe` function surfacing as `localFunction` models, local pipe chat execution through the parent function for selected manifold submodels, active `action` function routing from assistant messages with selected-message/thread/history context, `functions.write` admin-directory enforcement for write operations, `functions.execute` enforcement for execution, native/Open WebUI JSON export, JSON import actions, single-function JSON sharing, workspace-backup inclusion, and local audit events.
- `FunctionLibraryView` exposes native sidebar rows, type icons, active/global indicators, permission-aware management and run controls, recent test-run previews, a create/edit sheet with segmented type selection, active/global toggles, monospaced source editing, schema-default valves JSON generation, generated primitive valves field controls bound back to the raw JSON body, valves JSON editing, context-menu actions, single-function sharing, and import/export buttons.

Future work should add stronger Python execution isolation, nested/generated advanced visual field-by-field valves forms, sandbox entitlements, and richer audit logs.

## Skill Library

- `AppSkill` stores local workspace skill ID, name, body content, optional description, tags, active state, user/group access grants, and timestamps.
- `JSONSkillStorageService` persists skill records as local JSON files for the MVP.
- `SkillExportService` exports native skill bundles and raw Open WebUI skill records, and imports native bundles, raw native arrays, or Open WebUI-style skill records with `meta.tags` and `access_grants`.
- `AppStore` owns skill create, update, delete, tag/access-grant normalization, text/tag/active-state search, grant-aware active-skill chat system-context injection, disabled-feature blocking for skill writes/imports/file and open-panel import entry points/sharing/chat-context injection, `skills.write` admin-directory enforcement for write operations, native/Open WebUI JSON export, JSON import actions, and single-skill native share actions.
- `SkillLibraryView` exposes native sidebar rows, active indicators, text/tag/active-state search, permission-aware management controls, a create/edit sheet with tag and user/group grant editing, context-menu actions, single-skill sharing, and import/export controls.

Future work should add server-backed access enforcement and richer user/group picker ergonomics.

## Feedback Records

- `AppFeedback` mirrors Open WebUI's feedback shape with typed `data`, `meta`, optional `snapshot` payloads, and a local moderation status that defaults old records to pending.
- `AppFeedbackData` stores rating, model ID, sibling model IDs, reason, comment, and unknown extra JSON fields for forward-compatible import.
- `AppFeedbackMeta` stores arena state, chat ID, message ID, tags, and unknown extra JSON fields.
- `JSONFeedbackStorageService` persists feedback records as local JSON files for the MVP.
- `FeedbackExportService` exports native feedback bundles and raw Open WebUI feedback records, and imports native bundles, raw native arrays, or Open WebUI-style feedback records while preserving local moderation status.
- `FeedbackEvaluationService` computes model summaries from local feedback. Multi-model feedback adjusts Elo-style scores against sibling models; single-model feedback contributes volume, sentiment, and tags without creating fake head-to-head wins.
- `FeedbackAdminFilter` builds a query-weighted searchable feedback admin list across model IDs, ratings, moderation status, reasons, comments, tags, IDs, and chat snapshot titles. Exact/high-signal field matches rank ahead of weaker text matches, with newest-first ordering used as the tie-breaker.
- `ChatThreadView` exposes a native assistant-message feedback sheet for rating plus optional reason/comment.
- `AppStore.createFeedback` saves the feedback record and updates the visible message rating so chat state and feedback state stay aligned; user-facing feedback import/export records count-only audit events, and `AppStore.updateFeedbackModerationStatus` plus `AppStore.deleteFeedback` persist local admin triage changes and write local audit events.
- `EvaluationDashboardView` exposes native audited import/export controls, model feedback summaries, moderation status menus, delete confirmations, and a searchable feedback record list from the sidebar/detail pane.
- `AnalyticsService` computes a local-only `AnalyticsSummary` from in-memory persisted app state: chats, messages, model usage, daily model activity, feedback, knowledge, channels, notes, automations, calendars, and events.
- `AnalyticsExportService` writes that summary plus the secretless web-search network history summary as a versioned JSON bundle for local audit/export workflows, while decoding older bundles that predate the web-search field.
- `AnalyticsService.modelChats(modelID:threads:)` builds a local model drilldown from persisted chat messages, including matching chat IDs, message counts, token totals, and newest-message ordering.
- `AppAuditEvent` records security-relevant local events with action, outcome, summary, metadata, and timestamp fields, including count-only feedback import/export plus feedback moderation/delete actions.
- `JSONAuditLogStorageService` persists audit events under Application Support as one JSON file per event, sorted newest-first on load.
- `AuditLogExportService` exports audit events as a versioned local JSON bundle.
- `AnalyticsDashboardView` exposes analytics summaries, selectable model rows with recent chat drilldowns, web-search network-transparency summaries derived from local audit events, and recent audit events as a native sidebar/detail surface with export controls and labels the data path as no-telemetry local reporting. Analytics report export records an aggregate-only audit event with readable rows for secretless web-search run/host/API-key-use/failed/blocked counts, without copying chat titles, message content, queries, secrets, or report rows into audit metadata.

Future work should add bulk/permissioned feedback admin workflows, richer analytics charts, and broader audit coverage across every admin/security workflow.

## Admin Directory

- `AdminUser` stores local user ID, name, email, admin/user/pending role, and timestamps.
- `AdminGroup` stores local group ID, name, description, member IDs, flat permission grant strings, and timestamps.
- `AdminDirectorySnapshot` persists users and groups together so membership references stay consistent.
- `JSONAdminDirectoryStorageService` stores the local admin directory snapshot as JSON.
- `AdminDirectoryExportService` exports native admin directory bundles and imports native snapshots, Open WebUI-shaped user/group records, SCIM-shaped ListResponse resources, SCIM user `groups` membership references, SCIM role/userType hints, and SCIM group entitlement values into the local admin directory.
- `AppStore` owns user/group create, update, delete, member assignment, permission normalization, permission checks, non-content import/export audit events, and admin JSON import/export actions.
- `AdminDirectoryView` exposes native sidebar management for users, roles, groups, group members, group permissions, and import/export controls.
- `AppStore.currentUserID` tracks the active local user for native permission gates.
- `AppStore.userHasPermission` grants all permissions to local admins, denies pending users, and checks group grants for regular users.
- `AppStore.currentUserCanManageAdminDirectory` gates admin directory mutations, member changes, and user-facing import/export with `settings.write`; unmanaged local bootstrap state still allows setup before a directory user is configured.
- `AdminDirectoryView` disables create, edit, delete, import, and export controls when the current user lacks `settings.write`.
- Open WebUI nested group permissions are flattened into native permission keys such as `knowledge.write`; disabled permissions are not granted.
- SCIM group `entitlements.value` entries are imported as native flat permission keys and normalized with any Open WebUI native permission extension values.

Future work should add full nested permission schema enforcement, profile/status metadata, invitations, server-backed enforcement across every workflow, LDAP/SSO/SCIM integration, and audit logs.

## Notes

- `AppNote` stores native note title, content, and timestamps.
- `JSONNoteStorageService` persists note records as local JSON files for the MVP.
- `NoteExportService` exports native note bundles, exports raw Open WebUI-style note records, and imports either native bundles, raw native note arrays, or Open WebUI-style note records with `data.content.md`.
- `AppStore` owns note create, update, delete, pin/unpin, pinned-first sorting, title/content filtering, durable note link generation/resolution, copy-link pasteboard actions, disabled-feature blocking before note write/import mutations, note-to-chat attachment, native Markdown share actions, and note-to-knowledge import actions, `notes.write` admin-directory enforcement for write operations, non-content audit events for create/update/pin/delete, and JSON import/export actions.
- `NoteLibraryView` exposes native sidebar rows, pinned note indicators, local note search, permission-aware create/edit/delete/pin/import controls, note-to-chat attachment, copy-link actions, native Markdown sharing, linked-note focus highlighting, and export buttons.

Future work should add collaboration metadata, ranked/shared-note search, and richer document-style navigation.

## Automations

- `AppAutomation` stores local automation ID, user ID, name, prompt, model ID, RRULE schedule text, optional metadata, enabled state, run timestamps, and audit timestamps.
- `AppAutomationRun` stores each manual execution attempt with automation ID/name, model, prompt, streamed output, success/failure status, optional error message, and start/completion timestamps.
- `JSONAutomationStorageService` persists automation records as local JSON files for the MVP.
- `JSONAutomationRunStorageService` persists automation run records as local JSON files for auditability and reload history.
- `AutomationExportService` exports native automation bundles and raw Open WebUI automation records, and imports native bundles, raw native arrays, or Open WebUI-style automation records with `data.prompt`, `data.model_id`, `data.rrule`, `meta`, `is_active`, `last_run_at`, and `next_run_at`.
- `AutomationScheduleService` supports local daily and weekly scheduling from RRULE strings, including `INTERVAL` and weekly `BYDAY`, validates unsupported frequencies or invalid weekday tokens before save, previews the next run for the editor, and keeps `nextRunAt` current after create/update/toggle/run flows.
- `AppStore` owns automation create, update, delete, enable/pause, disabled-feature blocking before automation write/import/run mutations, provider streaming, open-panel import, and single-automation sharing, schedule validation before create/update, run-now execution through the active chat provider, active-provider chat capability preflight with failed-run persistence, an app-open scheduler loop for due automations gated by the Automations feature toggle, immediate scheduler cancellation when that toggle is disabled, virtual Scheduled Tasks calendar projection, run-history persistence, non-prompt lifecycle audit events, success/failure run audit events, local search, native/Open WebUI JSON export, JSON import actions, and single-automation JSON sharing, with `automations.write` required for local write and run operations.
- `AutomationLibraryView` exposes native sidebar rows, active/paused state, latest run status, provider capability hints, run-now action, a create/edit sheet with live RRULE validation and next-run preview, context-menu actions, single-automation sharing, and import/export buttons, disabling write/run controls when the current user lacks `automations.write`.

Future work should add closed-app scheduling, notification/webhook delivery, terminal config execution, user/group permissions, limits, and broader audit logs.

## Calendar

- `AppCalendar`, `AppCalendarEvent`, and `AppCalendarEventAttendee` model local calendars, stored events, and attendee RSVP state.
- `JSONCalendarStorageService` persists one calendar snapshot containing calendars plus events so event `calendarID` references stay together.
- `CalendarExportService` exports native full-calendar or single-event calendar bundles, exports raw Open WebUI calendar/event records with `access_grants`, and imports native snapshots, raw event arrays, or Open WebUI-style calendar/event records with `calendar_id`, `start_at`, `end_at`, `all_day`, `rrule`, reminder fields such as `reminder_minutes_before` or `meta.alert_minutes`, local user/group calendar access grants, `meta`, `attendees`, and nanosecond epoch timestamps.
- `CalendarRecurrenceService` expands daily, weekly, monthly, and simple yearly `rrule` values, including `INTERVAL`, `COUNT`, `UNTIL`, weekly `BYDAY`, monthly `BYMONTHDAY`, and yearly `BYMONTH`, into shifted event occurrences for visible date ranges; unsupported rules still display the original stored event if it overlaps the range.
- `CalendarMonthGridService` builds a six-week month grid from the current calendar, including leading/trailing days and per-day event buckets for single-day, multi-day, and expanded recurring events.
- `CalendarWeekGridService` builds a seven-day week grid from the current calendar, respecting the user's first weekday and per-day event buckets for single-day, multi-day, and expanded recurring events.
- `CalendarDayScheduleService` builds a day schedule with all-day events separated from timed events and timed events bucketed into every overlapping hour slot.
- `CalendarReminderNotificationService` maps due reminder occurrences into stable native notification requests, while `UserNotificationCalendarReminderDeliverer` requests alert/sound authorization and submits `UNUserNotificationCenter` requests.
- `AppStore` owns default Personal calendar creation, calendar create/delete, event create/update/delete, attendee add/update/remove with RSVP status persistence, disabled-feature blocking before calendar/event/attendee mutations, JSON import persistence, reminder notification delivery, reminder scheduler starts, and single-event sharing, local reminder-offset persistence, due-reminder range queries, app-open reminder notification scheduling with duplicate suppression, event RRULE persistence, cancellation state, recurring date-range filtering, calendar event search with free text plus `calendar:` and `status:` operators, user/group grant-aware visible calendars and event sources, virtual Scheduled Tasks calendar injection from active automations, month/week/day projection, JSON import/export, single-event JSON sharing, and calendar dashboard selection, with `calendar.write` required for local calendar/event/attendee write operations and non-content audit events recorded for event create/update/delete plus attendee add/update/remove.
- `CalendarSidebarView` exposes the sidebar entry and import/export controls; `CalendarDashboardView` exposes native calendar rows, a search field, calendar creation with user/group grant fields, a month/week/day segmented view, agenda rows, single-event sharing for stored events, a read-only system Scheduled Tasks calendar for automation occurrences, and an event editor sheet with attendee RSVP controls plus optional RRULE and reminder entry for stored calendars, disabling write controls when the current user lacks `calendar.write`.

Future work should add broader RRULE support beyond the current daily/weekly/monthly/simple-yearly subset, richer shared-calendar workflows, closed-app reminder guarantees, server-backed permission enforcement, and richer saved-search/filter workflows.

## Playground

- `AppStore` owns temporary playground state through `playgroundPrompt`, `playgroundSystemPrompt`, `playgroundModelID`, `playgroundOutput`, `playgroundError`, `playgroundNoteTitle`, `selectedPlaygroundNoteID`, and `isRunningPlayground`.
- `AppStore` also owns playground generation settings for temperature, top-p, and max tokens, then converts them into provider-neutral `ProviderChatOptions`.
- `AppStore` owns optional comparison state through `isPlaygroundComparisonEnabled`, `playgroundComparisonModelID`, `playgroundComparisonOutput`, and `playgroundComparisonError`.
- `AppStore` owns `playgroundHistory` and delegates persistence to `JSONPlaygroundHistoryStorageService`, which stores one local JSON file per saved temporary run.
- `AppStore.runPlayground` branches by `PlaygroundMode` after enforcing the Playground feature toggle. Chat, Completions, and Images require `playground.execute` before provider calls. Chat mode preflights the active provider's chat capability, builds provider messages from the optional system prompt plus user prompt, streams through the active `ChatProvider` with playground options, can run the same temporary request against a comparison model, and does not create or persist a `ChatThread`. Completions mode preflights the active provider's completions capability and streams the raw prompt through `ChatProvider.streamCompletion` without chat messages. Notes mode requires `notes.write` and saves or updates native `AppNote` records without calling a provider. Images mode preflights active-provider image-generation capability, sends an `ImageGenerationRequest`, and keeps generated image bytes as temporary playground outputs.
- `AppStore.saveCurrentPlaygroundRun` requires `playground.write` and snapshots the current mode, prompt, model selection, comparison state, image settings, image outputs, text output, and generation options into a `PlaygroundHistoryItem`; `loadPlaygroundHistoryItem` restores that state without creating chat or generated-image library records. `AppStore` also shares the current or saved run as a native JSON transcript bundle.
- `OllamaClient` maps `ProviderChatOptions` into the native Ollama `options` object for chat and raw completions, while `OpenAICompatibleClient` maps the same values into top-level chat-completion and completion request fields.
- `PlaygroundExportService` formats the current temporary run as either Open WebUI-style text sections or a versioned JSON transcript bundle that preserves mode, comparison output, generation options, and image playground outputs.
- `PlaygroundSidebarView` exposes the sidebar entry; `PlaygroundView` exposes Chat/Completions/Notes/Images mode switching, chat/completion model selection, comparison model selection, parameter controls, note selection/title controls, image model/size/quality/count controls, prompt/body editors, saved-run history controls, streamed output panes, note save status, image output thumbnails, clear/run controls, provider error display, current-run sharing, saved-run sharing, and text/JSON export buttons, disabling provider run controls without `playground.execute`, note save controls without `notes.write`, and saved-history mutation controls without `playground.write`.
- Selecting Playground clears chat, knowledge, channel, evaluation, analytics, and calendar selections so the detail pane has one active workflow.

Future work should add richer provider capability gating and mode-specific export polish.

## Provider Boundary

Provider adapters should expose common operations:

- `healthCheck()`
- `listModels()`
- `streamChat(request:)`
- `streamCompletion(request:)`
- `embeddings(request:)`
- `generateImages(request:)`, with a default unsupported-media error for providers that do not implement native image generation yet.
- `editImage(request:)`, `varyImage(request:)`, `transcribeAudio(request:)`, and `synthesizeSpeech(request:)`, with default unsupported errors for providers that do not implement those native media operations yet.

This keeps the UI from caring whether a response comes from Ollama, OpenAI-compatible APIs, or a future provider.

`ProviderCapabilities` describes which of those operations the active adapter supports. `AppStore` preflights chat, model management, embeddings, image generation/editing/variations, and audio STT/TTS before starting their workflows so unsupported providers show clear local errors instead of creating partial state or opening unnecessary network streams.

Model management is gated by `ProviderCapabilities.supportsModelManagement` and executed through a separate `OllamaModelManaging` protocol instead of the generic chat provider protocol. This keeps OpenAI-compatible providers from pretending they can pull or delete local Ollama models while leaving room for future model-management-capable adapters.

Ollama health checks use the official `GET /api/version`, `GET /api/tags`, and `GET /api/ps` endpoints, so the native status text can show runtime version, installed model count, and running model count.

## Security Defaults

- Store API keys and OAuth tokens in Keychain, not plain settings files.
- Keep provider status visible before sending data off-machine.
- Make network destinations explicit in settings.
- Do not scrape ChatGPT, reuse browser cookies, or call private endpoints.
- `OpenAIAccountAccessPolicy.current` keeps the current official OpenAI account status explicit in code and Settings: API-key provider access is supported, while ChatGPT subscription model access is blocked unless a supported native-app OAuth/account-linking path exists. The policy also carries official reference links and a last official review date so the unsupported state is auditable.
- Workspace backups include provider metadata but never export Keychain secret values.
- Audit logs are local JSON records; current coverage includes feature-toggle changes, analytics export with aggregate-only metadata and secretless web-search network-summary counts, feedback import/export with count-only metadata, prompt create/update/delete and import/export with count-only metadata, generated-image import/export with count-only metadata, tool create/update/delete without source content, local tool runs without source content, note create/update/pin/delete without note content, skill create/update/delete without skill content, function create/update/delete without source content/manifests/valves, admin user/group create/update/delete, group membership changes, admin directory import/export without directory content, workspace backup import/export with count-only metadata and no workspace content, audit-log export with count-only metadata, channel create/update/delete and member management without message content, calendar event/attendee changes without event content, feedback moderation/deletion, automation lifecycle changes without prompt content, automation runs, web-search runs with secretless contacted-host/API-key-use metadata and no query content plus local Analytics summary/export coverage, code-execution runs, direct tool-server invocations, and direct tool-server run deletion without request/response payloads, with export/delete controls and workspace-backup inclusion.
- Treat telemetry as opt-in, auditable, and removable.

## Current Provider Settings Model

`AppSettings` stores:

- Ollama base URL for backward compatibility with the first MVP.
- Provider configurations with name, type, base URL, enabled state, and optional Keychain secret ID.
- Active provider ID.
- Selected model ID for the active chat surface.
- Feature toggles for native and planned app surfaces.
- Web-search settings for engine, result count, optional SearXNG base URL, optional Brave API-key secret ID, domain filters, optional page-content loading, and page text length caps.

During decode, missing or empty provider lists restore the default Ollama provider, and stale active-provider IDs are normalized to the first available provider so upgraded or hand-edited settings files do not keep pointing at a removed provider. Provider switching rejects unavailable provider IDs before persistence and clears stale selection errors after a valid switch.

Provider switching validates the requested provider ID against the enabled provider list before changing or saving settings, so UI or command callers cannot persist an unknown active provider.

Provider API keys are never stored in `settings.json`; the app writes them through `KeychainSecretStore` and deletes the matching Keychain secret when an OpenAI-compatible provider is removed.

## Feature Toggles

- `AppFeatureToggle` names native and planned feature surfaces such as folders, knowledge, notes, tools, evaluations, web search, image generation, audio, voice mode, channels, automations, and code interpreter.
- `FeatureToggleSettings` stores only user-changed overrides from each feature's default state, so older settings files keep sane defaults.
- `AppStore.isFeatureEnabled(_:)` and `AppStore.setFeatureToggle(_:isEnabled:)` route feature-gate reads/writes through the persisted settings file.
- `SettingsView` exposes toggles for implemented native surfaces only.
- `SettingsView` also exposes workspace backup export/import. Restore replaces the local JSON-backed workspace records, refreshes visible state, leaves provider API keys in Keychain rather than exporting secret values, and records count-only backup audit events for user-facing import/export actions.
- `SidebarView` gates implemented sections and creation controls from the persisted toggle state.
- Code Interpreter is implemented but default-disabled, so local command execution is visible in Settings as an explicit opt-in native surface.

## Image Generation

- `ImageGenerationRequest`, `ImageEditRequest`, `ImageVariationRequest`, `ImageGenerationResult`, and `GeneratedImage` define the provider boundary for text-to-image generation, single-image editing, and image variations.
- `OpenAICompatibleClient.generateImages` sends JSON requests to `/images/generations`, requests model/prompt/size/quality/count, and decodes base64 image results plus revised prompt metadata.
- `OpenAICompatibleClient.editImage` sends multipart image edit requests to `/images/edits`, uploading the source image plus an optional mask image with model/prompt/size/quality/count fields and decoding base64 edited image results.
- `OpenAICompatibleClient.varyImage` sends multipart DALL-E 2 variation requests to `/images/variations`, uploads the source PNG, requests `b64_json` output, and decodes base64 variation results.
- `AppGeneratedImage` stores generated image bytes with prompt, model, provider, size, quality, output format, revised prompt metadata, and optional source image linkage plus source operation metadata for edited and variation outputs.
- `JSONGeneratedImageStorageService` persists generated image records under Application Support as one JSON file per image, sorted newest-first on load.
- `GeneratedImageExportService` exports/imports the image library as a versioned native JSON bundle, exports raw Open WebUI/OpenAI-style image response JSON with `b64_json` records plus local metadata, imports those raw image response records, and workspace backups include generated images alongside chats, knowledge, and other local surfaces.
- `AppStore` owns image-generation prompt controls, selected model, edit prompt/selection state, temporary edit-mask import state, request state, provider errors, generated image records, native/Open WebUI JSON import/export, persistence, and dashboard selection, with the Image Generation feature toggle enforced before generate/edit/variation provider calls and generated-image data/file/open-panel import/export entry points, `image_generation.execute` required before provider calls, `image_generation.write` required before replacing or exporting the generated-image library through user actions, and user-facing image-library import/export recording count-only audit events without image bytes, prompts, or revised prompts.
- `ImageGenerationView` exposes a native sidebar/detail surface with model, prompt, size, quality, count controls, active-provider generation/editing/variation execution, optional edit-mask import/clear controls, native/Open WebUI JSON import/export controls, and a generated image gallery, disabling generate/edit/variation controls without `image_generation.execute` and relying on store-level `image_generation.write` enforcement for import/export user actions.

Future work should add multi-image reference editing, deeper provider capability filtering, and broader media permissions.

## Audio

- `AudioTranscriptionRequest`, `AudioTranscriptionResult`, `SpeechSynthesisRequest`, and `SpeechSynthesisResult` define the provider boundary for native STT/TTS.
- `OpenAICompatibleClient.transcribeAudio` sends multipart form data to `/audio/transcriptions`, including model, response format, optional prompt/language fields, and the selected audio file part.
- `OpenAICompatibleClient.synthesizeSpeech` sends JSON to `/audio/speech`, including model, input, voice, optional instructions, and response format, then returns the raw audio bytes.
- `AppAudioHistoryItem` records local transcription and speech results with model metadata, source file metadata, voice/options, generated audio bytes where applicable, and timestamps.
- `JSONAudioHistoryStorageService` persists audio history under Application Support as one JSON file per result, sorted newest-first on load, and can replace the local history for imports.
- `AudioHistoryExportService` exports/imports transcription and speech history as a versioned native JSON bundle, preserving generated speech bytes while keeping user-facing audit metadata count-only.
- `AudioPlaybackControlling` abstracts local playback; `AVAudioPlaybackController` uses `AVAudioPlayer` for generated speech and persisted speech history bytes while tests inject a fake player.
- `AudioRecordingControlling` abstracts microphone capture and microphone permission checks; `AVAudioRecordingController` maps macOS audio authorization status through `AVCaptureDevice`, requests access when needed, uses `AVAudioRecorder` to record temporary AAC `.m4a` files, reads the bytes back as pending audio, and lets tests inject a fake recorder.
- `AppStore` owns audio selection, pending imported or recorded audio file data, transcription controls, microphone permission and recording state, speech controls, voice-mode orchestration from pending audio to normal chat streaming to optional synthesized assistant reply, provider model-name filtering/defaults for likely STT/TTS models, request state, generated speech bytes, output filename, playback state, persisted history, native JSON import/export, load/delete/play/pause/stop actions, workspace-backup inclusion, and provider errors, with the Audio feature toggle required before STT/TTS provider calls, microphone recording, pending-audio file/open-panel import, audio-history data/file/open-panel import entry points, audio-history user-action export, generated-speech playback, and saved audio-history load/play/delete actions, the Voice Mode feature toggle required before voice-mode provider calls, `audio.transcribe` required before STT provider calls and microphone recording, `audio.synthesize` required before TTS provider calls, and `audio.write` required before deleting, importing, or exporting audio history.
- `AudioView` exposes a native sidebar/detail surface with import, permission-aware microphone record/stop controls, transcription, Voice Chat orchestration for pending audio, transcript editing, capability-aware model pickers when likely STT/TTS models are known, speech synthesis, output format selection, save-to-disk controls, local play/pause/stop controls, and history import/export/load/delete/play controls, disabling STT/TTS/voice-mode and history mutation controls when the current user lacks the matching audio grant or provider capability.
- Audio is a default-enabled native feature toggle; Ollama currently reports clear unsupported-audio errors through the provider boundary.

Future work should add provider-reported per-model media capabilities where APIs expose them, local audio adapters where feasible, realtime duplex voice conversation, Developer ID signing/notarization validation, and broader media permission prompts.

## Web Search

- `WebSearchSettings`, `WebSearchEngine`, `WebSearchResult`, and `WebSearchTelemetry` define the native search configuration, result shape, optional loaded page text, and latest-search freshness metadata.
- `WebSearchService` supports DuckDuckGo HTML search without an API key, SearXNG JSON search for self-hosted search, Brave Search through the official web-search endpoint, and Tavily search through a Keychain-backed bearer token read by secret ID. It applies result limits and optional domain filters before returning snippets.
- When page-content loading is enabled, `WebSearchService` fetches each selected result URL, strips scripts/styles/tags for HTML/plain-text pages, extracts selectable text from PDF responses, normalizes whitespace, caps text length, and stores that cleaned page text on the result.
- `SettingsView` exposes search engine, result count, SearXNG base URL, Brave/Tavily API-key entry, comma-separated domain filters, page-content loading, and page text character caps; `WebSearchSettings` normalizes decoded and saved admin controls by trimming URLs/secret IDs/domains, removing duplicate domain filters, and clamping result/page-text limits to supported ranges.
- `ComposerView` exposes a globe toggle when the web-search feature is enabled. The toggle searches before the next send only, then resets after a successful prompt.
- `AppStore.webSearchCitations` fails closed when a stale or programmatic web-search request reaches the store while the Web Search feature toggle is disabled, before search network work or provider streaming begins.
- `AppStore.currentUserCanUseWebSearch` gates execution through the flat `web_search.execute` permission before any search network request is made; the composer disables its globe button for users without that grant.
- `AppStore.recentWebSearchResults` and `AppStore.recentWebSearchTelemetry` store the latest successful result set plus query, engine, result count, completion time, contacted hosts, and API-key-use status for native preview, and clear stale previews when a new search starts, search fails, web search is disabled, or permission blocks execution.
- Completed, failed, and blocked web-search attempts record local `webSearchRun` audit events with engine, status, result counts, contacted hosts, page-text loading state, and whether a Keychain API key was used. These audit events intentionally omit the search query, Keychain secret ID, and secret value.
- `ComposerView` renders compact web-result preview cards with freshness and local network transparency metadata, title, host, snippet or loaded page-text excerpt, and an external-link action after a web-search prompt runs.
- `AppStore.webSearchCitations` converts results into `ChatCitation` records with `collectionSlug == "web"`, so existing citation rendering, exports, and provider-context formatting can carry web sources without a separate message model.
- `AppStore.providerContent(for:)` injects loaded page text when available, or the search snippet as a fallback, into the user message as explicit web-search context before streaming starts.
- `WebSearchTelemetry` records local success/failure status, engine, result counts, page-content loading state, page-text enrichment counts, contacted hosts, whether a Keychain API key was used, completion time, and failure messages; the composer preview renders both the search summary and a secretless network summary for successful searches, while the audit log keeps a local network-transparency history.
- `WebSearchNetworkHistorySummary` derives local Analytics dashboard and analytics JSON export counts from `webSearchRun` audit events: total runs, succeeded/failed/blocked outcomes, Keychain API-key use, unique host count, most recent run time, and top contacted hosts.
- If search fails, the app records failed local telemetry, surfaces the error before calling the provider, and leaves the toggle on so the user can retry after fixing settings or network access.

Future work should add provider capability checks, additional API-key engines such as SearchApi where useful, broader binary web extraction, and richer network transparency history drilldowns.

Future work should continue connecting planned toggles to their completed workflows, map Open WebUI's nested feature permission schema, and enforce feature gates in command menus and service entry points in addition to sidebar visibility.

## Code Interpreter

- `CodeExecutionLanguage`, `CodeExecutionRequest`, `CodeExecutionStatus`, and `AppCodeExecutionRun` model local code execution as auditable records with language, code, optional working directory, stdout, stderr, exit code, status, and timestamps.
- `CodeExecutionSettings` and `CodeExecutionPolicy` define the first native execution policy layer: allowed languages, allowed working-directory roots, executable allow/deny lists, and max timeout. Blocked requests surface a clear reason before `Process` is launched.
- `CodeExecutionService` uses macOS `Process` to run explicit user-triggered shell snippets through `/bin/zsh -lc` or Python snippets through `/usr/bin/python3 -c`. It captures stdout/stderr with bounded `Pipe` readers, applies timeout and maximum-output limits, terminates slow or over-budget runs, and records failed launches as failed runs.
- `JSONCodeExecutionStorageService` persists run history under Application Support as one JSON file per run, sorted newest-first on load.
- `AppStore` owns code-interpreter input state, disabled-feature enforcement before local process launch and run-history deletion, `code.execute` admin-directory enforcement for running code and deleting run history, timeout, working directory, policy checks, blocked-run errors, selected history item, persisted history, content-free deletion audit markers, workspace-backup inclusion, and navigation selection.
- `CodeInterpreterView` exposes a native sidebar/detail surface with language picker, timeout stepper, optional working directory, code editor, permission-aware run actions, output/stderr panels, status display, and history reload/delete actions.
- `SettingsView` exposes the code-execution policy controls, including executable allow/deny lists, alongside feature toggles, while the policy model also enforces persisted capture limits so local command execution remains explicit and bounded.
- `AppTerminalSession` and `AppTerminalCommand` model native terminal sessions as persisted shell command transcripts with session ID, command text, working directory, stdout, stderr, exit code, status, and timestamps.
- `JSONTerminalSessionStorageService` persists sessions and command transcripts as local JSON records sorted newest-first.
- `AppStore` exposes terminal session creation/update/deletion and one-command-at-a-time shell execution behind the Terminal Sessions feature toggle, reuses `CodeExecutionPolicy` and `CodeExecutionService`, requires `terminal.execute` for shell runs, requires `terminal.write` for session metadata edits and session/transcript deletion, allows either permission to create a session record, records local audit events for session lifecycle changes and command run/content-free deletion markers, and includes terminal sessions/commands in workspace backups.
- `TerminalSessionView` exposes a permission-aware native sidebar/detail surface with session creation/editing/deletion, working-directory capture and editing, command input, timeout control, transcript output, transcript rerun drafting, and transcript deletion.

Future work should add stronger sandboxing, provider tool-call routing, live PTY terminal streaming, MCP/OpenAPI tool servers, CPU/memory-style resource limits, and richer audit logs.

## Channels

- `AppChannel`, `ChannelMessage`, `ChannelReply`, and `ChannelMember` model the local-native channel surface with metadata, unread counts, embedded messages, threaded replies, and member role/status/mute/pin state.
- `JSONChannelStorageService` stores one channel JSON file per channel under Application Support for simple create/update/delete persistence.
- `ChannelExportService` exports native channel bundles and raw Open WebUI channel records, and imports native bundles, channel arrays, and tolerant Open WebUI-shaped channel/member/reply records.
- `AppStore` owns channel state through `channels`, `selectedChannelID`, `channelSearchText`, and channel mutation methods for create, update, delete, member management, message posting, reply posting, selection, unread clearing, filtering, native/Open WebUI JSON export, and JSON import, with disabled-feature blocking for channel create/update/delete/message/reply/member/import/select mutations, `channels.write` required for local write operations, and non-content audit events recorded for channel create/update/delete plus member add/update/remove.
- `ChannelLibraryView` renders the sidebar channel list, editor sheet, and import/export controls; `ChannelDetailView` renders selected channel messages, threaded replies, members, and the composer, disabling write controls when the current user lacks `channels.write`.
- Selecting a channel clears chat, knowledge, and evaluation selections so the native detail pane has one active workflow at a time.

Future work should add realtime socket/event integration, server-backed channel membership enforcement, full Open WebUI message/member migration, channel search tools, and admin controls.
