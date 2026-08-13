import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?
  private var urlLauncherChannel: FlutterMethodChannel?
  private var windowChannel: FlutterMethodChannel?
  private var savedBrightness: CGFloat?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerPrivacyChannel(messenger)
    registerUrlLauncherChannel(messenger)
    registerWindowChannel(messenger)
  }

  private func registerPrivacyChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.privi.app/privacy",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "setAppSwitcherShield" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let enabled = arguments["enabled"] as? Bool
      else {
        result(
          FlutterError(
            code: "invalid_arguments",
            message: "The privacy shield requires a boolean enabled value.",
            details: nil
          )
        )
        return
      }
      DispatchQueue.main.async {
        PrivacyShieldCoordinator.shared.setEnabled(enabled)
        result(nil)
      }
    }
    privacyChannel = channel
  }

  private func registerUrlLauncherChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.privi.app/url_launcher",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "openUrl" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard
        let arguments = call.arguments as? [String: Any],
        let value = arguments["url"] as? String,
        let url = URL(string: value),
        let scheme = url.scheme?.lowercased(),
        scheme == "https" || scheme == "http"
      else {
        result(
          FlutterError(
            code: "invalid_url",
            message: "Only HTTP and HTTPS URLs can be opened.",
            details: nil
          )
        )
        return
      }
      DispatchQueue.main.async {
        UIApplication.shared.open(url, options: [:]) { opened in
          result(opened)
        }
      }
    }
    urlLauncherChannel = channel
  }

  private func registerWindowChannel(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "com.privi.app/window",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        switch call.method {
        case "getBrightness":
          result(Double(UIScreen.main.brightness))
        case "setBrightness":
          guard
            let arguments = call.arguments as? [String: Any],
            let value = arguments["value"] as? Double
          else {
            result(
              FlutterError(
                code: "invalid_arguments",
                message: "Brightness requires a 0–1 value.",
                details: nil
              )
            )
            return
          }
          if self?.savedBrightness == nil {
            self?.savedBrightness = UIScreen.main.brightness
          }
          UIScreen.main.brightness = CGFloat(min(max(value, 0), 1))
          result(nil)
        case "resetBrightness":
          if let saved = self?.savedBrightness {
            UIScreen.main.brightness = saved
            self?.savedBrightness = nil
          }
          result(nil)
        case "getVolume", "setVolume":
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    windowChannel = channel
  }
}
