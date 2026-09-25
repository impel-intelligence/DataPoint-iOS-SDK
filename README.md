# DataPoint iOS SDK

Monetize your app with micro-tasks via the DataPoint iOS SDK.

## Installation

### Swift Package Manager (Recommended)

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/trydatapoint/datapoint-ios-sdk.git", from: "1.1.0")
]
```

Or in Xcode: **File → Add Package Dependencies** → Enter the repository URL.

## Usage

### Initialize the SDK

```swift
import DataPointSDK

DataPoint.initialize(apiKey: "YOUR_API_KEY") { result in
    switch result {
    case .success:
        print("SDK initialized")
    case .failure(let error):
        print("Failed: \(error)")
    }
}
```

### Set User ID (Optional)

```swift
DataPoint.setAppUserId("user123") { result in
    // Handle result
}
```

### Show Tasks

```swift
DataPoint.setListener(self)
DataPoint.showTasks(from: viewController)
```

### Implement DataPointListener

```swift
extension YourClass: DataPointListener {
    func onTaskCompleted(_ payload: String?) {
        // User completed a task
    }
    
    func onAdRequested() {
        // Show an ad
    }
    
    func noTaskAvailable() {
        // No tasks available
    }
    
    func onClosed() {
        // Task screen closed
    }
    
    func onError(message: String, code: Int) {
        // Handle error
    }

    // Optional: host app went to background / returned while the task UI was visible.
    func onAppLifecycleEvent(_ state: DataPointAppLifecycleState) {
        // .didEnterBackground or .willEnterForeground
    }
}
```

## Opening Links in a Browser

Task pages on DataPoint domains render inside the SDK's `WKWebView`. Anything else leaves it:

| The page does                                     | Where it opens                                          |
| ------------------------------------------------- | ------------------------------------------------------- |
| Link / redirect to a non-DataPoint `http(s)` host | In-app `SFSafariViewController`                         |
| `target="_blank"` link / `window.open`            | In-app browser (or the WebView, if the host is DataPoint) |
| `mailto:` `tel:` `itms-apps:` …                   | The app that handles that scheme                        |
| `javascript:` `file:` `data:` `about:`            | Blocked                                                 |

The task screen stays presented underneath, so closing the browser returns the user to their
task. If a task completes while the browser is open, the task screen is dismissed once the
browser closes. Which target a task's CTA uses (in-app or external) is configured per job in
DataPoint, not in your app.

## Requirements

- iOS 13.0+
- Swift 5.9+

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.
