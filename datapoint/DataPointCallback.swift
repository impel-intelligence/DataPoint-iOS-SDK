import Foundation

/// Callback for asynchronous SDK operations such as user attributes.
public protocol DataPointCallback: AnyObject {
    func onSuccess()
    func onError(message: String, code: Int)
}
