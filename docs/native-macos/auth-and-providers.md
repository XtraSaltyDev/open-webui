# Native macOS Auth And Providers

## Current Supported Provider Modes

### Ollama

- Default base URL: `http://localhost:11434`
- Model listing: `GET /api/tags`
- Health check: base URL reachability plus model endpoint availability
- Streaming chat: `POST /api/chat`
- Secret storage: none for the default local setup

### OpenAI-Compatible API

- Default base URL suggestion: `https://api.openai.com/v1`
- Model listing: `GET /models`
- Health check: base URL reachability plus model endpoint availability
- Streaming chat: `POST /chat/completions` with `stream: true`
- Streaming completions: `POST /completions` with `stream: true`
- Embeddings: `POST /embeddings`
- Image generation: `POST /images/generations`
- Image editing: `POST /images/edits`
- Image variations: `POST /images/variations`
- Audio transcription: `POST /audio/transcriptions`
- Speech synthesis: `POST /audio/speech`
- Authentication: `Authorization: Bearer <api key>`
- Secret storage: API key stored in macOS Keychain; settings keep only `apiKeySecretID`
- Removal: deleting the provider removes its Keychain API key and falls back to Ollama if it was active

## ChatGPT Subscription Access

The native app must not scrape ChatGPT, reuse browser cookies, or call private endpoints.

Verified against official OpenAI docs on 2026-06-03:

- OpenAI API authentication uses bearer credentials from API keys or short-lived workload identity federation access tokens.
- OpenAI Help says ChatGPT subscriptions and API service are billed and managed separately.
- OpenAI Help also describes ChatGPT and the API platform as separate billing systems.

Because of that, direct model access through a user's ChatGPT subscription is blocked unless OpenAI publishes an official native-app OAuth or account-linking flow for API model use. The native Settings view exposes this as an explicit account-access status rather than offering a fake or private ChatGPT sign-in path.

Official references:

- https://developers.openai.com/api/reference/overview#authentication
- https://help.openai.com/en/articles/8156019-is-api-usage-included-in-chatgpt-subscriptions-even-if-i-have-a-paid-chatgpt-account
- https://help.openai.com/en/articles/9039756-managing-your-work-in-the-api-platform-with-projects

## Implementation Notes

- `ChatProvider` defines the shared provider operations.
- `OllamaClient` and `OpenAICompatibleClient` implement `ChatProvider`.
- `ProviderFactory` chooses the correct adapter from `ProviderConfiguration`.
- `ProviderCapabilities` lets the app preflight active-provider support for chat, model management, embeddings, image generation/editing/variations, and audio STT/TTS before starting those workflows.
- Image generation, single-image editing, and DALL-E 2 image variations are exposed through the shared provider boundary. Ollama uses the default unsupported-media errors until native image-capable local adapters are added; OpenAI-compatible providers use the Image API-compatible `/images/generations`, `/images/edits`, and `/images/variations` paths.
- Audio transcription and speech synthesis are exposed through the same provider boundary. Ollama uses default unsupported-audio errors until a local audio adapter is added; OpenAI-compatible providers use multipart `/audio/transcriptions` requests and JSON `/audio/speech` requests.
- Settings exposes an explicit provider health check and displays the active provider status.
- `OpenAIAccountAccessPolicy.current` encodes the current supported mode, blocked subscription status, official reference links, last official review date, and guardrails against cookie reuse/private endpoints.
- `KeychainSecretStore` wraps generic-password Keychain APIs.
- `InMemorySecretStore` is used by unit tests and can support future previews.

## Verification

- `OpenAIAccountAccessPolicyTests` verifies that account OAuth is not presented as supported, that API-key auth is the supported mode, that official reference evidence is tracked, and that cookie/private-endpoint access remains disallowed.
- `OpenAICompatibleClientTests` verifies bearer auth, model decoding, streaming delta parsing, embeddings decoding, image generation request/response handling, multipart image edit and variation request/response handling, audio transcription multipart requests, and speech synthesis JSON requests.
- `SecretStoreTests` verifies both in-memory and real macOS Keychain save/update/read/delete behavior.
- `AppStoreProviderSettingsTests` verifies active-provider health status routing and provider removal deletes the stored secret and clears removed-provider model selections.
