# DataPoint iOS SDK

Monetize your app with micro-tasks via the DataPoint iOS SDK.

## Installation

### Swift Package Manager (Recommended)

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/trydatapoint/datapoint-ios-sdk.git", from: "1.0.0")
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
}
```

## Requirements

- iOS 13.0+
- Swift 5.9+

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.
