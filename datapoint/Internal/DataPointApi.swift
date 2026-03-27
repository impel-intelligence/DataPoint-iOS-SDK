import Foundation

enum DataPointApi {

    struct InitResponse {
        let userId: String
        let externalUserId: String
        let appId: String
        let sessionToken: String
        let expiresIn: Int64
    }

    enum ApiResult<T> {
        case success(T)
        case error(message: String, httpCode: Int)
    }

    private static let maxInitAttempts = 3
    private static let retryBaseDelayNs: UInt64 = 1_000_000_000

    static func validate(
        baseURL: String,
        apiKey: String,
        userId: String?,
        deviceId: String,
        timestamp: Int64,
        environment: String,
        sdkInfo: [String: Any],
        appInfo: [String: Any],
        deviceInfo: [String: Any],
        displayInfo: [String: Any],
        networkInfo: [String: Any],
        localeInfo: [String: Any],
        batteryInfo: [String: Any],
        identifiersInfo: [String: Any],
        privacyInfo: [String: Any]
    ) -> ApiResult<InitResponse> {
        var body: [String: Any] = [
            "api_key": apiKey,
            "device_id": deviceId,
            "timestamp": timestamp,
            "environment": environment,
            "sdk": sdkInfo,
            "app": appInfo,
            "device": deviceInfo,
            "display": displayInfo,
            "network": networkInfo,
            "locale": localeInfo,
            "battery": batteryInfo,
            "identifiers": identifiersInfo,
            "privacy": privacyInfo
        ]
        if let userId, !userId.isEmpty {
            body["user_id"] = userId
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body, options: []) else {
            return .error(message: "Failed to encode request", httpCode: 0)
        }

        var lastResult: ApiResult<InitResponse> = .error(message: "Initialization failed", httpCode: 0)
        let endpoint = baseURL + SdkConstants.validateEndpoint

        for attempt in 1...maxInitAttempts {
            guard let url = URL(string: endpoint) else {
                return .error(message: "Invalid URL", httpCode: 0)
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.httpBody = jsonData
            request.timeoutInterval = 30

            DataPointLogger.d("POST \(url.path) attempt \(attempt)/\(maxInitAttempts) (body omitted)")

            let semaphore = DispatchSemaphore(value: 0)
            var completed: ApiResult<InitResponse> = .error(message: "Network error", httpCode: 0)

            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                defer { semaphore.signal() }

                if let error {
                    DataPointLogger.e("Validate request failed (attempt \(attempt)/\(maxInitAttempts))", error: error)
                    completed = .error(message: error.localizedDescription, httpCode: 0)
                    return
                }

                let http = response as? HTTPURLResponse
                let code = http?.statusCode ?? 0
                let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""

                DataPointLogger.d("initialize response http=\(code) bytes=\(bodyString.count) (body omitted)")

                if (500...599).contains(code) {
                    let msg = parseErrorMessage(bodyString, httpCode: code)
                    completed = .error(message: msg, httpCode: code)
                    return
                }

                if !(200...299).contains(code) {
                    let msg = parseErrorMessage(bodyString, httpCode: code)
                    completed = .error(message: msg, httpCode: code)
                    return
                }

                guard let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completed = .error(message: "Invalid response", httpCode: code)
                    return
                }

                if (json["status"] as? String) != "success" {
                    let msg = (json["message"] as? String) ?? "Initialization failed"
                    completed = .error(message: msg, httpCode: code)
                    return
                }

                guard let dataObj = json["data"] as? [String: Any] else {
                    completed = .error(message: "Invalid response: missing 'data'", httpCode: code)
                    return
                }

                let initResponse = InitResponse(
                    userId: dataObj["user_id"] as? String ?? "",
                    externalUserId: dataObj["external_user_id"] as? String ?? "",
                    appId: dataObj["app_id"] as? String ?? "",
                    sessionToken: dataObj["session_token"] as? String ?? "",
                    expiresIn: (dataObj["expires_in"] as? NSNumber)?.int64Value ?? 86_400
                )
                completed = .success(initResponse)
            }
            task.resume()
            semaphore.wait()

            let result = completed
            lastResult = result

            switch result {
            case .success:
                return result
            case .error(let message, let httpCode):
                if (500...599).contains(httpCode), attempt < maxInitAttempts {
                    let delay = UInt64(attempt) * retryBaseDelayNs
                    DataPointLogger.w("Server error (\(httpCode)), retrying in \(delay / 1_000_000)ms")
                    Thread.sleep(forTimeInterval: TimeInterval(delay) / 1_000_000_000.0)
                    continue
                }
                if httpCode == 0, attempt < maxInitAttempts {
                    let delay = UInt64(attempt) * retryBaseDelayNs
                    DataPointLogger.w("Retrying in \(delay / 1_000_000)ms…")
                    Thread.sleep(forTimeInterval: TimeInterval(delay) / 1_000_000_000.0)
                    continue
                }
                return result
            }
        }

        return lastResult
    }

    static func setAttributes(
        baseURL: String,
        sessionToken: String,
        attributes: [String: Any]
    ) -> ApiResult<Void> {
        let endpoint = baseURL + SdkConstants.userAttributesEndpoint
        guard let url = URL(string: endpoint) else {
            return .error(message: "Invalid URL", httpCode: 0)
        }

        let attrsObj = NSMutableDictionary()
        for (k, v) in attributes {
            attrsObj[k] = v
        }
        let body: [String: Any] = ["attributes": attrsObj]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return .error(message: "Failed to encode request", httpCode: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        DataPointLogger.d("PUT \(url.path) (request body omitted)")

        let sem = DispatchSemaphore(value: 0)
        var out: ApiResult<Void> = .error(message: "Network error", httpCode: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            if let error {
                DataPointLogger.e("Set attributes request failed", error: error)
                out = .error(message: error.localizedDescription, httpCode: 0)
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DataPointLogger.d("setAttributes response http=\(code) bytes=\(bodyString.count) (body omitted)")
            if (200...299).contains(code) {
                out = .success(())
            } else {
                out = .error(message: parseErrorMessage(bodyString, httpCode: code), httpCode: code)
            }
        }.resume()

        sem.wait()
        return out
    }

    static func setAppUserId(
        baseURL: String,
        sessionToken: String,
        appUserId: String
    ) -> ApiResult<Void> {
        let endpoint = baseURL + SdkConstants.assignAppUserIdEndpoint
        guard let url = URL(string: endpoint) else {
            return .error(message: "Invalid URL", httpCode: 0)
        }

        let body: [String: Any] = ["app_user_id": appUserId]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            return .error(message: "Failed to encode request", httpCode: 0)
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(sessionToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = jsonData
        request.timeoutInterval = 30

        DataPointLogger.d("POST \(url.path) (request body omitted)")

        let sem = DispatchSemaphore(value: 0)
        var out: ApiResult<Void> = .error(message: "Network error", httpCode: 0)

        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { sem.signal() }
            if let error {
                DataPointLogger.e("assign_app_user_id request failed", error: error)
                out = .error(message: error.localizedDescription, httpCode: 0)
                return
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let bodyString = data.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            DataPointLogger.d("assign_app_user_id response http=\(code) bytes=\(bodyString.count) (body omitted)")
            if (200...299).contains(code) {
                out = .success(())
            } else {
                out = .error(message: parseErrorMessage(bodyString, httpCode: code), httpCode: code)
            }
        }.resume()

        sem.wait()
        return out
    }

    static func parseErrorMessage(_ body: String?, httpCode: Int) -> String {
        guard let body, !body.isEmpty else { return "Request failed (\(httpCode))" }
        guard let data = body.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "Request failed (\(httpCode))"
        }
        let detail = (json["detail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !detail.isEmpty { return detail }
        let message = (json["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !message.isEmpty { return message }
        return "Request failed (\(httpCode))"
    }

    static func httpCodeToErrorCode(_ httpCode: Int) -> Int {
        switch httpCode {
        case 400:
            return ErrorCode.invalidRequest.rawValue
        case 401:
            return ErrorCode.invalidApiKey.rawValue
        case 500...599:
            return ErrorCode.serverError.rawValue
        case 0:
            return ErrorCode.networkError.rawValue
        default:
            return ErrorCode.initializationFailed.rawValue
        }
    }
}
