import Foundation

/// Error codes returned by SDK callbacks (aligned with Android).
public enum ErrorCode: Int, Sendable {
    /// `DataPoint.initialize` has not been called or has not completed.
    case sdkNotInitialized = 1001
    /// The initialization network request failed.
    case initializationFailed = 1002
    /// The session token expired and automatic re-initialization failed.
    case sessionExpired = 1003
    /// Invalid parameters passed to the SDK (e.g. blank apiKey).
    case invalidConfiguration = 1004
    /// `showTasks` was called while the task screen is already visible.
    case taskAlreadyShowing = 1005
    /// A generic network error (no connectivity, timeout, etc.).
    case networkError = 1007
    /// Invalid request parameters sent to the server (HTTP 400).
    case invalidRequest = 1008
    /// The API key is invalid or unauthorized (HTTP 401).
    case invalidApiKey = 1009
    /// The server encountered an internal error (HTTP 5xx).
    case serverError = 1012
}
