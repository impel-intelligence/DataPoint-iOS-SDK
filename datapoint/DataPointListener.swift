import Foundation

/// Callback interface for task-related events. Set via `DataPoint.setListener`.
public protocol DataPointListener: AnyObject {
    /// A task was completed. `payload` is the raw JSON string from the WebView, or `nil`.
    func onTaskCompleted(_ payload: String?)

    /// The WebView requested that the host app show an ad. The task screen is closed before this fires.
    func onAdRequested()

    /// No tasks are currently available; the task screen is closed before this fires.
    func noTaskAvailable()

    /// The task screen was dismissed (user, WebView, or `closeTasks()`).
    func onClosed()

    /// An error occurred.
    func onError(message: String, code: Int)
}
