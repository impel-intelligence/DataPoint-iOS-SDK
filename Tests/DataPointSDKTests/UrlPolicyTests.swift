import XCTest
@testable import DataPointSDK

final class UrlPolicyTests: XCTestCase {

    func testWebSchemesAreHttpAndHttpsCaseInsensitive() {
        XCTAssertTrue(UrlPolicy.isWebScheme("http"))
        XCTAssertTrue(UrlPolicy.isWebScheme("HTTPS"))
        XCTAssertFalse(UrlPolicy.isWebScheme("mailto"))
        XCTAssertFalse(UrlPolicy.isWebScheme("itms-apps"))
        XCTAssertFalse(UrlPolicy.isWebScheme(nil))
    }

    func testSchemesThatReachBackIntoTheAppAreBlocked() {
        for scheme in ["javascript", "file", "data", "about", "JavaScript"] {
            XCTAssertTrue(UrlPolicy.isBlockedScheme(scheme), scheme)
        }
        XCTAssertFalse(UrlPolicy.isBlockedScheme("https"))
        XCTAssertFalse(UrlPolicy.isBlockedScheme("tel"))
        XCTAssertFalse(UrlPolicy.isBlockedScheme(nil))
    }

    func testTrustedHostsMatchExactlyOrAsSubdomains() {
        XCTAssertTrue(UrlPolicy.isTrustedHost("trydatapoint.com"))
        XCTAssertTrue(UrlPolicy.isTrustedHost("task.trydatapoint.com"))
        XCTAssertTrue(UrlPolicy.isTrustedHost("api.trydatapoint.com"))
        XCTAssertTrue(UrlPolicy.isTrustedHost("TASK.TRYDATAPOINT.COM"))
        XCTAssertTrue(UrlPolicy.isTrustedHost("trydatapoint.ai"))
    }

    func testLookAlikeAndUnrelatedHostsAreNotTrusted() {
        XCTAssertFalse(UrlPolicy.isTrustedHost("evil-trydatapoint.com"))
        XCTAssertFalse(UrlPolicy.isTrustedHost("trydatapoint.com.evil.io"))
        XCTAssertFalse(UrlPolicy.isTrustedHost("example.com"))
        XCTAssertFalse(UrlPolicy.isTrustedHost(""))
        XCTAssertFalse(UrlPolicy.isTrustedHost(nil))
    }

    func testModeParsing() {
        XCTAssertTrue(UrlPolicy.wantsSystemBrowser("external"))
        XCTAssertTrue(UrlPolicy.wantsSystemBrowser("browser"))
        XCTAssertTrue(UrlPolicy.wantsSystemBrowser("system"))
        XCTAssertTrue(UrlPolicy.wantsSystemBrowser(" External "))
        XCTAssertFalse(UrlPolicy.wantsSystemBrowser("in_app"))
        XCTAssertFalse(UrlPolicy.wantsSystemBrowser("custom_tab"))
        XCTAssertFalse(UrlPolicy.wantsSystemBrowser(""))
        XCTAssertFalse(UrlPolicy.wantsSystemBrowser(nil))
    }

    func testSanitizedURLAcceptsUsableLinks() {
        XCTAssertEqual(UrlPolicy.sanitizedExternalURL("https://example.com/offer?x=1")?.absoluteString,
                       "https://example.com/offer?x=1")
        XCTAssertEqual(UrlPolicy.sanitizedExternalURL("  https://apps.apple.com/us/app/id544007664 ")?.host,
                       "apps.apple.com")
        XCTAssertEqual(UrlPolicy.sanitizedExternalURL("mailto:hello@example.com")?.scheme, "mailto")
        XCTAssertEqual(UrlPolicy.sanitizedExternalURL("itms-apps://apps.apple.com/app/id1")?.scheme, "itms-apps")
    }

    func testSanitizedURLRejectsUnusableLinks() {
        XCTAssertNil(UrlPolicy.sanitizedExternalURL(""))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("   "))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("javascript:alert(1)"))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("file:///etc/passwd"))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("data:text/html,hi"))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("about:blank"))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("http:foo"))
        XCTAssertNil(UrlPolicy.sanitizedExternalURL("not a url"))
    }
}
