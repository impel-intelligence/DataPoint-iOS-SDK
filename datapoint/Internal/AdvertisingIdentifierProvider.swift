import AdSupport
import AppTrackingTransparency
import Foundation
import UIKit

/// Best-effort IDFA collection with Limit Ad Tracking parity to Android.
enum AdvertisingIdentifierProvider {
    static func fetchAdvertisingId(completion: @escaping (_ id: String?, _ limitAdTracking: Bool) -> Void) {
        DispatchQueue.main.async {
            if #available(iOS 14, *) {
                let status = ATTrackingManager.trackingAuthorizationStatus
                switch status {
                case .authorized:
                    let id = ASIdentifierManager.shared().advertisingIdentifier
                    let uuid = id.uuidString
                    let isZero = uuid == "00000000-0000-0000-0000-000000000000"
                    completion(isZero ? nil : uuid, false)
                case .denied, .restricted, .notDetermined:
                    if status == .notDetermined {
                        ATTrackingManager.requestTrackingAuthorization { newStatus in
                            DispatchQueue.main.async {
                                Self.fetchAdvertisingId(completion: completion)
                            }
                        }
                        return
                    }
                    completion(nil, true)
                @unknown default:
                    completion(nil, true)
                }
            } else {
                let id = ASIdentifierManager.shared().advertisingIdentifier
                if id.uuidString == "00000000-0000-0000-0000-000000000000" {
                    completion(nil, true)
                } else {
                    completion(id.uuidString, false)
                }
            }
        }
    }
}
