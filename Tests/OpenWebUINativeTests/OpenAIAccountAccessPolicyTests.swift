import XCTest
@testable import OpenWebUINative

final class OpenAIAccountAccessPolicyTests: XCTestCase {
    func testCurrentPolicyBlocksChatGPTSubscriptionModelAccessWithoutOfficialOAuthSupport() {
        let policy = OpenAIAccountAccessPolicy.current

        XCTAssertFalse(policy.isAccountOAuthSupportedForModelUse)
        XCTAssertEqual(policy.supportedAuthenticationMode, .apiKey)
        XCTAssertEqual(policy.subscriptionAccessStatus, .blocked)
        XCTAssertTrue(policy.requiresSeparateAPIBilling)
    }

    func testCurrentPolicyDisallowsScrapingCookiesAndPrivateEndpoints() {
        let policy = OpenAIAccountAccessPolicy.current

        XCTAssertFalse(policy.allowsBrowserCookieReuse)
        XCTAssertFalse(policy.allowsPrivateEndpointAccess)
        XCTAssertTrue(policy.guardrails.contains(.noBrowserCookies))
        XCTAssertTrue(policy.guardrails.contains(.noPrivateEndpoints))
        XCTAssertTrue(policy.guardrails.contains(.keychainSecretsOnly))
    }

    func testCurrentPolicyTracksOfficialReferenceEvidence() {
        let policy = OpenAIAccountAccessPolicy.current

        XCTAssertEqual(policy.lastOfficialReviewDate, "2026-06-03")
        XCTAssertEqual(
            policy.officialReferences.map(\.url.absoluteString),
            [
                "https://developers.openai.com/api/reference/overview#authentication",
                "https://help.openai.com/en/articles/8156019-is-api-usage-included-in-chatgpt-subscriptions-even-if-i-have-a-paid-chatgpt-account",
                "https://help.openai.com/en/articles/9039756-managing-your-work-in-the-api-platform-with-projects"
            ]
        )
        XCTAssertEqual(
            policy.officialReferences.map(\.title),
            [
                "OpenAI API authentication",
                "ChatGPT subscription to API billing",
                "ChatGPT and API billing settings"
            ]
        )
    }
}
