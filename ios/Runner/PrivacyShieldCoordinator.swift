import UIKit

final class PrivacyShieldCoordinator {
  static let shared = PrivacyShieldCoordinator()

  private let overlayTag = 0x50524956
  private var enabled = false
  private var captureObserver: NSObjectProtocol?

  private init() {
    captureObserver = NotificationCenter.default.addObserver(
      forName: UIScreen.capturedDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      self?.refreshConnectedScenes()
    }
  }

  func setEnabled(_ enabled: Bool) {
    self.enabled = enabled
    refreshConnectedScenes()
  }

  func sceneWillResignActive(_ scene: UIScene) {
    guard enabled, let windowScene = scene as? UIWindowScene else { return }
    installOverlay(in: windowScene)
  }

  func sceneDidEnterBackground(_ scene: UIScene) {
    guard enabled, let windowScene = scene as? UIWindowScene else { return }
    installOverlay(in: windowScene)
  }

  func sceneDidBecomeActive(_ scene: UIScene) {
    guard let windowScene = scene as? UIWindowScene else { return }
    if enabled && UIScreen.main.isCaptured {
      installOverlay(in: windowScene)
    } else {
      removeOverlay(from: windowScene)
    }
  }

  private func refreshConnectedScenes() {
    for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
      guard enabled else {
        removeOverlay(from: scene)
        continue
      }
      if scene.activationState == .foregroundActive && !UIScreen.main.isCaptured {
        removeOverlay(from: scene)
      } else {
        installOverlay(in: scene)
      }
    }
  }

  private func installOverlay(in scene: UIWindowScene) {
    guard let window = scene.windows.first(where: { $0.isKeyWindow }) ?? scene.windows.first else {
      return
    }
    if let overlay = window.viewWithTag(overlayTag) {
      overlay.frame = window.bounds
      window.bringSubviewToFront(overlay)
      return
    }

    let overlay = UIView(frame: window.bounds)
    overlay.tag = overlayTag
    overlay.backgroundColor = .black
    overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    overlay.isUserInteractionEnabled = true
    overlay.accessibilityElementsHidden = true
    window.addSubview(overlay)
  }

  private func removeOverlay(from scene: UIWindowScene) {
    for window in scene.windows {
      window.viewWithTag(overlayTag)?.removeFromSuperview()
    }
  }
}
