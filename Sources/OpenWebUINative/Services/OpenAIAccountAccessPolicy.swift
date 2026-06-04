import Foundation

struct OpenAIAccountAccessPolicy: Equatable, Sendable {
    struct OfficialReference: Equatable, Identifiable, Sendable {
        var title: String
        var url: URL

        var id: String {
            url.absoluteString
        }
    }

    enum AuthenticationMode: String, Equatable, Sendable {
        case apiKey = "API key"
    }

    enum SubscriptionAccessStatus: String, Equatable, Sendable {
        case blocked = "Blocked"
    }

    enum Guardrail: String, CaseIterable, Equatable, Sendable {
        case noBrowserCookies
        case noPrivateEndpoints
        case keychainSecretsOnly
        case separateAPIBilling

        var label: String {
            switch self {
            case .noBrowserCookies:
                return "Do not reuse browser cookies or ChatGPT sessions."
            case .noPrivateEndpoints:
                return "Do not call private or undocumented ChatGPT endpoints."
            case .keychainSecretsOnly:
                return "Store supported provider secrets only in Keychain."
            case .separateAPIBilling:
                return "Treat ChatGPT subscription access and API billing as separate."
            }
        }
    }

    var isAccountOAuthSupportedForModelUse: Bool
    var supportedAuthenticationMode: AuthenticationMode
    var subscriptionAccessStatus: SubscriptionAccessStatus
    var requiresSeparateAPIBilling: Bool
    var allowsBrowserCookieReuse: Bool
    var allowsPrivateEndpointAccess: Bool
    var guardrails: [Guardrail]
    var lastOfficialReviewDate: String
    var officialReferences: [OfficialReference]

    static let current = OpenAIAccountAccessPolicy(
        isAccountOAuthSupportedForModelUse: false,
        supportedAuthenticationMode: .apiKey,
        subscriptionAccessStatus: .blocked,
        requiresSeparateAPIBilling: true,
        allowsBrowserCookieReuse: false,
        allowsPrivateEndpointAccess: false,
        guardrails: [
            .noBrowserCookies,
            .noPrivateEndpoints,
            .keychainSecretsOnly,
            .separateAPIBilling
        ],
        lastOfficialReviewDate: "2026-06-03",
        officialReferences: [
            OfficialReference(
                title: "OpenAI API authentication",
                url: URL(string: "https://developers.openai.com/api/reference/overview#authentication")!
            ),
            OfficialReference(
                title: "ChatGPT subscription to API billing",
                url: URL(
                    string: "https://help.openai.com/en/articles/8156019-is-api-usage-included-in-chatgpt-subscriptions-even-if-i-have-a-paid-chatgpt-account"
                )!
            ),
            OfficialReference(
                title: "ChatGPT and API billing settings",
                url: URL(string: "https://help.openai.com/en/articles/9039756-managing-your-work-in-the-api-platform-with-projects")!
            )
        ]
    )
}
