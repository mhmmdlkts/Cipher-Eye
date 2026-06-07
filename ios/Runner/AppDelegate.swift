import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var captureCover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    // Cover the UI whenever the screen is being recorded or mirrored (AirPlay),
    // so stored passwords don't leak into a recording/cast.
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(updateCaptureCover),
      name: UIScreen.capturedDidChangeNotification,
      object: nil)
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc private func updateCaptureCover() {
    if UIScreen.main.isCaptured {
      guard captureCover == nil, let window = activeWindow() else { return }
      let cover = UIView(frame: window.bounds)
      cover.backgroundColor = UIColor(red: 0.196, green: 0.380, blue: 0.310, alpha: 1.0)
      cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
      window.addSubview(cover)
      captureCover = cover
    } else {
      captureCover?.removeFromSuperview()
      captureCover = nil
    }
  }

  /// The current key window, fetched via the connected scenes (the AppDelegate's
  /// own `window` is nil in this scene-based setup).
  private func activeWindow() -> UIWindow? {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap { $0.windows }
    return windows.first { $0.isKeyWindow } ?? windows.first
  }
}
