import Foundation

/// SDK environment configuration.
///
/// - `production` — Connects to the live backend; performs real validation.
/// - `sandbox` — Connects to the QA backend; performs real validation.
public enum Environment: String, Sendable {
    case production = "PRODUCTION"
    case sandbox = "SANDBOX"
}
