import Foundation

/// Pure rules for where a URL may go. Kept free of UIKit/WebKit so the policy is
/// unit-testable; `TaskWebViewController` applies it to real navigations.
enum UrlPolicy {

    /// Schemes an in-app browser can render.
    private static let webSchemes: Set<String> = ["http", "https"]

    /// Schemes a remote page must never be able to hand to the SDK.
    private static let blockedSchemes: Set<String> = ["javascript", "file", "data", "about"]

    /// `mode` values that select the system browser instead of the in-app one.
    private static let systemBrowserModes: Set<String> = ["external", "browser", "system"]

    /// `true` for `http`/`https`; every other scheme belongs to another app.
    static func isWebScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased() else { return false }
        return webSchemes.contains(s)
    }

    /// `true` for schemes that could reach back into the app and must be refused outright.
    static func isBlockedScheme(_ scheme: String?) -> Bool {
        guard let s = scheme?.lowercased() else { return false }
        return blockedSchemes.contains(s)
    }

    /// `true` when `host` is one of `SdkConstants.trustedHosts` or a subdomain of one.
    /// A plain suffix match is not enough: `evil-trydatapoint.com` must not pass.
    static func isTrustedHost(_ host: String?) -> Bool {
        guard let h = host?.lowercased(), !h.isEmpty else { return false }
        return SdkConstants.trustedHosts.contains { h == $0 || h.hasSuffix(".\($0)") }
    }

    /// Parses the `mode` argument from JS. `"external"`, `"browser"` and `"system"`
    /// mean the system browser; anything else (or `nil`) means in-app.
    static func wantsSystemBrowser(_ mode: String?) -> Bool {
        let m = (mode ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return systemBrowserModes.contains(m)
    }

    /// Parses `raw` and rejects schemes that would let a page reach back into the app,
    /// plus web URLs with no resolvable host. Returns `nil` for anything unusable.
    static func sanitizedExternalURL(_ raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else { return nil }
        if isBlockedScheme(scheme) { return nil }
        if isWebScheme(scheme), (url.host?.isEmpty ?? true) { return nil }
        return url
    }
}
