import Foundation

enum LogSanitizer {
    static func secretLength(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "nil" }
        return "len=\(value.count)"
    }

    static func safeErrorSnippet(_ message: String?, max: Int = 120) -> String {
        guard let message, !message.isEmpty else { return "(no message)" }
        if message.count <= max { return message }
        return String(message.prefix(max)) + "…"
    }

    static func urlForLog(_ url: String) -> String {
        guard let components = URLComponents(string: url) else { return "(invalid url)" }
        var c = components
        c.query = nil
        c.fragment = nil
        return c.string ?? url
    }
}
