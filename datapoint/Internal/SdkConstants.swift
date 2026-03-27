import Foundation

enum SdkConstants {
    static let sdkVersion = "1.0.1"
    static let platform = "ios"

    static let productionBaseURL = "https://api.trydatapoint.com/data-labelling/v1"
    static let validateEndpoint = "/initialize"
    static let userAttributesEndpoint = "/user/attributes"
    static let assignAppUserIdEndpoint = "/assign_app_user_id"

    static let productionTaskURL = "https://task.trydatapoint.com/"
    static let sandboxTaskURL = productionTaskURL

    static let jsBridgeTask = "DataPointTask"
    static let jsBridgeApp = "DataPointApp"
    static let jsBridgeAudio = "AudioVolumeHelper"

    static let trustedHosts = ["trydatapoint.com", "trydatapoint.ai"]

    static let prefsName = "datapoint_sdk_prefs"
    static let prefDeviceId = "device_id"
    static let prefSessionToken = "session_token"
    static let prefSessionExpiry = "session_expiry"
    static let prefUserId = "user_id"
    static let prefExternalUserId = "external_user_id"
    static let prefApiKey = "api_key"
    static let prefAppId = "app_id"
    static let prefInstallId = "install_id"
}
