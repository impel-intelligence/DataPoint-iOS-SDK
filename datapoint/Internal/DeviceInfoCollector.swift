import CoreTelephony
import Foundation
import Network
import UIKit

enum DeviceInfoCollector {

    /// Must be called on the main thread (uses `UIScreen` / `UIDevice`).
    static func collectSdkInfo() -> [String: Any] {
        [
            "sdk_version": SdkConstants.sdkVersion,
            "sdk_platform": SdkConstants.platform
        ]
    }

    static func collectAppInfo(sha256Cert: String?) -> [String: Any] {
        let bundle = Bundle.main
        var result: [String: Any] = [
            "package_name": bundle.bundleIdentifier ?? "",
            "app_name": bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "",
            "app_version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "build_number": Int(bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0") ?? 0
        ]
        if let sha256Cert, !sha256Cert.isEmpty {
            result["sha256_cert"] = sha256Cert
        }
        return result
    }

    /// Main-thread only.
    static func collectDeviceInfo() -> [String: Any] {
        let processInfo = ProcessInfo.processInfo
        let physicalMemoryMb = Int(processInfo.physicalMemory / (1024 * 1024))

        let fileURL = URL(fileURLWithPath: NSHomeDirectory())
        let resourceValues: URLResourceValues
        do {
            resourceValues = try fileURL.resourceValues(forKeys: [
                .volumeAvailableCapacityForImportantUsageKey,
                .volumeTotalCapacityKey
            ])
        } catch {
            resourceValues = URLResourceValues()
        }
        let storageTotalMb = max(0, (resourceValues.volumeTotalCapacity ?? 0) / (1024 * 1024))
        let storageAvailableMb = max(0, Int((resourceValues.volumeAvailableCapacityForImportantUsage ?? 0) / (1024 * 1024)))

        let deviceType: String = UIDevice.current.userInterfaceIdiom == .pad ? "tablet" : "phone"

        return [
            "platform": SdkConstants.platform,
            "manufacturer": "Apple",
            "brand": "Apple",
            "model": machineModelName(),
            "device_type": deviceType,
            "os": "iOS",
            "os_version": UIDevice.current.systemVersion,
            "sdk_int": Int(UIDevice.current.systemVersion.split(separator: ".").first ?? "0") ?? 0,
            "cpu_architecture": cpuArchitecture(),
            "ram_mb": physicalMemoryMb,
            "storage_total_mb": storageTotalMb,
            "storage_available_mb": storageAvailableMb
        ]
    }

    /// Main-thread only.
    static func collectDisplayInfo() -> [String: Any] {
        let screen = UIScreen.main
        let bounds = screen.bounds
        let scale = screen.scale
        let widthPx = Int(bounds.width * scale)
        let heightPx = Int(bounds.height * scale)
        let nativeScale = screen.nativeScale
        let densityDpi = Int(160 * nativeScale)

        let widthInches = Double(widthPx) / Double(max(densityDpi, 1))
        let heightInches = Double(heightPx) / Double(max(densityDpi, 1))
        let diagonal = sqrt(widthInches * widthInches + heightInches * heightInches)

        let orientation = bounds.width > bounds.height ? "landscape" : "portrait"

        return [
            "screen_resolution": "\(widthPx)x\(heightPx)",
            "screen_density": densityDpi,
            "orientation": orientation,
            "screen_size_inches": diagonal
        ]
    }

    static func collectNetworkInfo() -> [String: Any] {
        let (networkType, connectionType) = currentNetworkTypes()
        let carrier: String = {
            let info = CTTelephonyNetworkInfo()
            if #available(iOS 12.0, *) {
                return info.serviceSubscriberCellularProviders?.values.compactMap(\.carrierName).first ?? ""
            }
            return info.subscriberCellularProvider?.carrierName ?? ""
        }()

        return [
            "network_type": networkType,
            "carrier": carrier,
            "connection_type": connectionType
        ]
    }

    static func collectLocaleInfo() -> [String: Any] {
        let locale = Locale.current
        let tz = TimeZone.current
        let language = Locale.preferredLanguages.first?.split(separator: "-").first.map(String.init) ?? ""
        let currency: String
        if #available(iOS 16.0, *) {
            currency = locale.currency?.identifier ?? ""
        } else {
            currency = locale.currencyCode ?? ""
        }
        let country: String
        if #available(iOS 16.0, *) {
            country = locale.region?.identifier ?? ""
        } else {
            country = locale.regionCode ?? ""
        }

        return [
            "language": language,
            "locale": locale.identifier,
            "timezone": tz.identifier,
            "country": country,
            "currency": currency
        ]
    }

    /// Main-thread only (`UIDevice.batteryLevel`).
    static func collectBatteryInfo() -> [String: Any] {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        let percent = level >= 0 ? Int(level * 100) : -1
        return ["battery_level": percent]
    }

    static func collectIdentifiers(advertisingId: String?, installId: String, vendorId: String?) -> [String: Any] {
        var dict: [String: Any] = [
            "install_id": installId
        ]
        if let advertisingId, !advertisingId.isEmpty {
            dict["advertising_id"] = advertisingId
        }
        if let vendorId, !vendorId.isEmpty {
            dict["vendor_id"] = vendorId
        }
        return dict
    }

    static func collectPrivacy(limitAdTracking: Bool) -> [String: Any] {
        ["limit_ad_tracking": limitAdTracking]
    }

    // MARK: - Helpers

    private static func machineModelName() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let mirror = Mirror(reflecting: systemInfo.machine)
        return mirror.children.reduce("") { acc, elem in
            guard let v = elem.value as? Int8, v != 0 else { return acc }
            return acc + String(UnicodeScalar(UInt8(v)))
        }
    }

    private static func cpuArchitecture() -> String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    private static func currentNetworkTypes() -> (networkType: String, connectionType: String) {
        let monitor = NWPathMonitor()
        let queue = DispatchQueue(label: "com.datapoint.sdk.path")
        var result: (String, String) = ("unknown", "unknown")
        let sem = DispatchSemaphore(value: 0)
        var didSignal = false
        monitor.pathUpdateHandler = { path in
            defer {
                if !didSignal {
                    didSignal = true
                    sem.signal()
                }
            }
            if path.status != .satisfied {
                result = ("unknown", "offline")
                return
            }
            if path.usesInterfaceType(.wifi) {
                result = ("wifi", "wifi")
            } else if path.usesInterfaceType(.cellular) {
                result = ("cellular", "cellular")
            } else if path.usesInterfaceType(.wiredEthernet) {
                result = ("ethernet", "ethernet")
            } else if path.usesInterfaceType(.other) {
                result = ("other", "other")
            }
        }
        monitor.start(queue: queue)
        _ = sem.wait(timeout: .now() + 0.75)
        monitor.cancel()
        return result
    }
}
