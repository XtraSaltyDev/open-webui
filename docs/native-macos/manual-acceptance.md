# Native macOS Manual Acceptance Checklist

Run this click-through after automated validation passes:

```bash
swift test
swift build
./script/build_and_run.sh --package
./script/build_and_run.sh --smoke
git diff --check
```

## Setup And Safety

- [ ] Launch a fresh app data directory and complete first-run setup.
- [ ] Open Settings and confirm Diagnostics shows app paths, provider health, chat counts, selected chat, selected models, active streams, and no secret values.
- [ ] Add or verify an Ollama provider without exposing secrets.
- [ ] Add or verify an OpenAI-compatible provider with its API key stored through Keychain only.
- [ ] Trigger a missing provider/API-key path and confirm the error is clear and does not print the key.
- [ ] Confirm Local Execution is disabled by default.
- [ ] Create a safety backup, reveal the backup folder, and restore a disposable backup.

## Model And Provider Flow

- [ ] Refresh models from the toolbar or Command+R.
- [ ] Switch models and confirm the selected model remains valid after refresh.
- [ ] If Ollama has no models, confirm the UI suggests starting Ollama or pulling a model.
- [ ] If an OpenAI-compatible provider has no models, confirm the UI suggests checking base URL, API key, and model endpoint.
- [ ] Select multiple models and confirm the UI clearly shows the selected count.
- [ ] Confirm Ollama pull/delete actions only appear for providers that support native model management.

## Composer Flow

- [ ] Type a normal message and send with Command+Enter.
- [ ] Use Shift+Enter in the composer and confirm it inserts a newline.
- [ ] Press Escape and confirm focus/transient composer UI clears without deleting draft text.
- [ ] Try an empty or whitespace-only send and confirm an inline message appears.
- [ ] Attach a pending file, remove it before send, and confirm the pending pill updates.
- [ ] Simulate provider/model refresh failure and confirm the draft text remains.
- [ ] Send successfully and confirm the composer clears and focus returns.
- [ ] Cause a pre-stream provider failure and confirm the draft and pending attachments remain.

## Streaming And Recovery

- [ ] Send to Ollama and confirm the active assistant message visibly shows generation state.
- [ ] Send to multiple selected models and confirm the composer reports how many responses are still generating.
- [ ] Stop all generation and confirm every active assistant response finalizes.
- [ ] Stop one assistant branch and confirm sibling branches keep streaming.
- [ ] Switch to another chat while a response streams, then return and confirm the original response finalized cleanly.
- [ ] Cause a provider stream failure and confirm the assistant bubble shows a retryable error.
- [ ] Quit/reopen after interrupting a stream and confirm no message reloads as permanently streaming.

## Retry, Regenerate, And Transcript Actions

- [ ] Regenerate a normal assistant response and confirm the user message is not duplicated.
- [ ] Regenerate with provider setup broken and confirm the old response remains until a replacement stream starts.
- [ ] Retry a failed assistant message and confirm it uses the preceding conversation context and model when possible.
- [ ] For multi-model branches, regenerate/retry one branch and confirm sibling branches are preserved.
- [ ] Edit a user message and confirm the transcript updates predictably.
- [ ] Copy one message and confirm long code blocks remain copyable.
- [ ] Copy the whole chat as Markdown with Command+Shift+C.
- [ ] Export a chat as native JSON and Open WebUI-compatible JSON.
- [ ] Restart the app and confirm chats, messages, attachments, ratings, and exports still load.

## Reading Flow

- [ ] Confirm user and assistant messages remain visually distinct at desktop and compact widths.
- [ ] Confirm streaming text stays readable while updating.
- [ ] Confirm assistant error text is visually distinct from normal answer text.
- [ ] Confirm token usage and generation duration are compact and do not crowd normal reading.
- [ ] Search or open a deep link to a message and confirm scroll/highlight is noticeable but not harsh.
- [ ] Open an empty chat and confirm the empty state explains how to start.
