import Foundation
import os.log

enum DataPointLogger {
    private static let subsystem = Bundle(for: DataPointBundleToken.self).bundleIdentifier ?? "com.trydatapoint.datapoint"
    private static let log = OSLog(subsystem: subsystem, category: "DataPoint")

    static var isEnabled = false

    static func d(_ message: String) {
        guard isEnabled else { return }
        os_log("%{public}@", log: log, type: .debug, message)
    }

    static func w(_ message: String) {
        guard isEnabled else { return }
        os_log("%{public}@", log: log, type: .default, message)
    }

    static func e(_ message: String, error: Error? = nil) {
        guard isEnabled else { return }
        if let error {
            os_log("%{public}@ — %{public}@", log: log, type: .error, message, String(describing: error))
        } else {
            os_log("%{public}@", log: log, type: .error, message)
        }
    }
}

/// Anchor class for resolving the framework bundle in `DataPointLogger`.
private final class DataPointBundleToken {}
