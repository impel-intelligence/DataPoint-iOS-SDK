import AVFoundation
import Foundation
import MediaPlayer
import UIKit
import WebKit

/// Bridges device media-volume controls and a `WKWebView` (Android `AudioVolumeHelper` parity).
final class WebViewAudioVolumeHelper: NSObject, WKScriptMessageHandler {

    private static let lowVolumeThreshold: Float = 0.30
    private static let nudgeVolume: Float = 0.35

    private weak var webView: WKWebView?

    private let volumeView: MPVolumeView = {
        let view = MPVolumeView(frame: CGRect(x: -1000, y: -1000, width: 1, height: 1))
        view.isHidden = false
        view.alpha = 0.01
        view.clipsToBounds = true
        return view
    }()

    private var volumeObservation: NSKeyValueObservation?
    private var isSessionActive = false
    private var lastPushedPercent: Int = -1

    func attach(to webView: WKWebView) {
        self.webView = webView

        webView.configuration.userContentController.add(self, name: SdkConstants.jsBridgeAudio)

        activateAudioSessionIfNeeded()
        let initialPercent = volumePercent()
        injectJavaScriptShim(into: webView, initialVolume: initialPercent)

        if let parent = webView.superview {
            parent.addSubview(volumeView)
        } else {
            webView.addSubview(volumeView)
        }

        startObservingVolume()
        registerForAppLifecycleNotifications()
    }

    func stopObserving() {
        volumeObservation?.invalidate()
        volumeObservation = nil
        NotificationCenter.default.removeObserver(self)

        webView?.configuration.userContentController.removeScriptMessageHandler(forName: SdkConstants.jsBridgeAudio)

        volumeView.removeFromSuperview()
        webView = nil
    }

    deinit {
        stopObserving()
    }

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard message.name == SdkConstants.jsBridgeAudio else { return }

        guard let body = message.body as? [String: Any],
              let method = body["method"] as? String else {
            return
        }

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            switch method {
            case "onAudioStarted":
                self.handleAudioStarted()

            case "getVolume":
                self.handleGetVolume()

            case "setVolume":
                if let percent = body["percent"] as? Int {
                    self.handleSetVolume(percent: percent)
                } else if let percent = body["percent"] as? Double {
                    self.handleSetVolume(percent: Int(percent))
                }

            default:
                break
            }
        }
    }

    private func handleAudioStarted() {
        activateAudioSessionIfNeeded()
        let currentVolume = AVAudioSession.sharedInstance().outputVolume

        if currentVolume < Self.lowVolumeThreshold {
            setSystemVolume(Self.nudgeVolume)
        }

        let percent = volumePercent()
        pushVolumeToWebView(percent)
    }

    private func handleGetVolume() {
        activateAudioSessionIfNeeded()
        let percent = volumePercent()

        webView?.evaluateJavaScript(
            "window.__iosCurrentVolume=\(percent);" +
            "if(typeof window.onVolumeResult==='function'){window.onVolumeResult(\(percent));}"
        )
    }

    private func handleSetVolume(percent: Int) {
        let clamped = min(max(percent, 0), 100)
        let floatValue = Float(clamped) / 100.0

        setSystemVolume(floatValue)

        pushVolumeToWebView(clamped)
    }

    private func setSystemVolume(_ value: Float) {
        guard let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider else {
            return
        }
        DispatchQueue.main.async {
            slider.value = value
            slider.sendActions(for: .valueChanged)
        }
    }

    private func pushVolumeToWebView(_ percent: Int) {
        guard percent != lastPushedPercent else { return }
        lastPushedPercent = percent

        webView?.evaluateJavaScript(
            "window.__iosCurrentVolume=\(percent);" +
            "if(typeof window.onVolumeChanged==='function'){window.onVolumeChanged(\(percent));}"
        )
    }

    private func volumePercent() -> Int {
        let volume = AVAudioSession.sharedInstance().outputVolume
        return Int(round(volume * 100))
    }

    private func activateAudioSessionIfNeeded() {
        guard !isSessionActive else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            isSessionActive = true
        } catch {
            // Best-effort; volume reads may still work.
        }
    }

    private func reactivateAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            isSessionActive = true
        } catch {
            // ignore
        }
    }

    private func registerForAppLifecycleNotifications() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidBecomeActive),
            name: UIApplication.didBecomeActiveNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
    }

    @objc private func appDidBecomeActive() {
        reactivateAudioSession()

        if volumeObservation == nil {
            startObservingVolume()
        }

        let percent = volumePercent()
        pushVolumeToWebView(percent)
    }

    @objc private func appDidEnterBackground() {
        isSessionActive = false
    }

    private func startObservingVolume() {
        volumeObservation?.invalidate()

        let session = AVAudioSession.sharedInstance()

        volumeObservation = session.observe(
            \.outputVolume,
            options: [.new]
        ) { [weak self] _, change in
            guard let self, let newValue = change.newValue else { return }

            let percent = Int(round(newValue * 100))

            DispatchQueue.main.async {
                self.pushVolumeToWebView(percent)
            }
        }
    }

    private func injectJavaScriptShim(into webView: WKWebView, initialVolume: Int) {
        let js = """
        (function() {
            if (window.AudioVolumeHelper) return;

            window.__iosCurrentVolume = \(initialVolume);

            window.AudioVolumeHelper = {
                onAudioStarted: function() {
                    window.webkit.messageHandlers.\(SdkConstants.jsBridgeAudio).postMessage({
                        method: 'onAudioStarted'
                    });
                },
                getVolume: function() {
                    window.webkit.messageHandlers.\(SdkConstants.jsBridgeAudio).postMessage({
                        method: 'getVolume'
                    });
                    return window.__iosCurrentVolume;
                },
                setVolume: function(percent) {
                    window.webkit.messageHandlers.\(SdkConstants.jsBridgeAudio).postMessage({
                        method: 'setVolume',
                        percent: percent
                    });
                }
            };
        })();
        """

        let userScript = WKUserScript(
            source: js,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true
        )

        webView.configuration.userContentController.addUserScript(userScript)
    }
}
