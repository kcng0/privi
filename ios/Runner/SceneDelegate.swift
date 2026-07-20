import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func sceneWillResignActive(_ scene: UIScene) {
    PrivacyShieldCoordinator.shared.sceneWillResignActive(scene)
    super.sceneWillResignActive(scene)
  }

  override func sceneDidEnterBackground(_ scene: UIScene) {
    PrivacyShieldCoordinator.shared.sceneDidEnterBackground(scene)
    super.sceneDidEnterBackground(scene)
  }

  override func sceneDidBecomeActive(_ scene: UIScene) {
    super.sceneDidBecomeActive(scene)
    PrivacyShieldCoordinator.shared.sceneDidBecomeActive(scene)
  }
}
