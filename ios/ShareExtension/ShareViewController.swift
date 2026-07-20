import receive_sharing_intent

final class ShareViewController: RSIShareViewController {
  override func shouldAutoRedirect() -> Bool {
    true
  }
}
