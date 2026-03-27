import Foundation

/// Optional callback for `DataPoint.initialize`.
public protocol InitCallback: AnyObject {
    func onSuccess()
    func onError(message: String, code: Int)
}
