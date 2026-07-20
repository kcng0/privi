import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?
  private var urlLauncherChannel: FlutterMethodChannel?

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
}
