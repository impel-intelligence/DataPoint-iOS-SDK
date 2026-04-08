import Foundation

import UIKit

/// Persistent key-value store for the SDK (UserDefaults).
final class DataPointPreferences {
    private let defaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.defaults = userDefaults
    }

    /// Stable device identifier (prefer `identifierForVendor`, else UUID).
    var deviceId: String {
        if let existing = defaults.string(forKey: SdkConstants.prefDeviceId), !existing.isEmpty {
            return existing
        }
        let id = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        defaults.set(id, forKey: SdkConstants.prefDeviceId)
        DataPointLogger.d("Device ID generated and stored (value omitted)")
        return id
    }

    var sessionToken: String? {
        get { defaults.string(forKey: SdkConstants.prefSessionToken) }
        set { defaults.set(newValue, forKey: SdkConstants.prefSessionToken) }
    }

    var sessionExpiry: TimeInterval {
        get { defaults.double(forKey: SdkConstants.prefSessionExpiry) }
        set { defaults.set(newValue, forKey: SdkConstants.prefSessionExpiry) }
    }

    func isSessionValid() -> Bool {
        guard let token = sessionToken, !token.isEmpty else { return false }
        let expiry = sessionExpiry
        if expiry == 0 { return false }
        return Date().timeIntervalSince1970 < expiry
    }

    func clearSession() {
        defaults.removeObject(forKey: SdkConstants.prefSessionToken)
        defaults.removeObject(forKey: SdkConstants.prefSessionExpiry)
    }

    var installId: String {
        if let existing = defaults.string(forKey: SdkConstants.prefInstallId), !existing.isEmpty {
            return existing
        }
        let id = UUID().uuidString
        defaults.set(id, forKey: SdkConstants.prefInstallId)
        DataPointLogger.d("Install ID generated and stored (value omitted)")
        return id
    }

    var userId: String? {
        get { defaults.string(forKey: SdkConstants.prefUserId) }
        set { defaults.set(newValue, forKey: SdkConstants.prefUserId) }
    }

    var externalUserId: String? {
        get { defaults.string(forKey: SdkConstants.prefExternalUserId) }
        set { defaults.set(newValue, forKey: SdkConstants.prefExternalUserId) }
    }

    var apiKey: String? {
        get { defaults.string(forKey: SdkConstants.prefApiKey) }
        set { defaults.set(newValue, forKey: SdkConstants.prefApiKey) }
    }

    var appId: String? {
        get { defaults.string(forKey: SdkConstants.prefAppId) }
        set { defaults.set(newValue, forKey: SdkConstants.prefAppId) }
    }
}
