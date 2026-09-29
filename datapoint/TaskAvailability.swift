import Foundation

/// Result of `DataPoint.checkTaskAvailability`.
public struct TaskAvailability: Equatable {
    /// `true` when `DataPoint.showTasks` would have a task to show right now.
    public let isAvailable: Bool
    /// Machine-readable explanation; see the `Reason` constants.
    public let reason: String
    /// Human-readable form of `reason`, for logs and debugging rather than end users.
    public let message: String

    public enum Reason {
        /// A task is available.
        public static let available = "available"
        /// No task matches this user right now.
        public static let noTask = "no_task"
        /// The user has completed today's maximum number of tasks.
        public static let dailyLimitReached = "daily_limit_reached"
        /// The user is not eligible to receive tasks.
        public static let accessDisabled = "access_disabled"
    }

    public init(isAvailable: Bool, reason: String, message: String) {
        self.isAvailable = isAvailable
        self.reason = reason
        self.message = message
    }

    /// Parses the `/availability` response body. Missing `reason`/`message` fall back to
    /// values derived from `task_available` so older backends still yield a usable result.
    init?(json: [String: Any]) {
        guard let available = json["task_available"] as? Bool else { return nil }
        self.isAvailable = available
        self.reason = (json["reason"] as? String) ?? (available ? Reason.available : Reason.noTask)
        self.message = (json["message"] as? String) ?? ""
    }
}

/// Failure of an SDK call that returns a value.
public struct DataPointError: Error, Equatable {
    /// Human-readable description.
    public let message: String
    /// Machine-readable code from `ErrorCode`.
    public let code: Int

    public init(message: String, code: Int) {
        self.message = message
        self.code = code
    }
}
