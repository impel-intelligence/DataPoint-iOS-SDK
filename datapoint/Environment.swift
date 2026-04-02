import Foundation

/// SDK environment configuration.
///
/// - `production` — Connects to the live backend; performs real validation.
/// - `sandbox` — Uses mock session data; skips network during initialization. API calls that do run (e.g. attributes) use the QA base URL (`qa-api`).
public enum Environment: String, Sendable {
    case production = "PRODUCTION"
    case sandbox = "SANDBOX"
}
