import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var didRegisterHaptics = false
  private var hapticRegistrationAttempts = 0

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    let ok = super.application(application, didFinishLaunchingWithOptions: launchOptions)
    setupNativeHapticsChannel()
    return ok
  }

  /// Scene 生命周期下首帧前 `window` 可能尚不可用，必要时短暂重试。
  private func setupNativeHapticsChannel() {
    guard !didRegisterHaptics else { return }
    guard let messenger = flutterBinaryMessenger() else {
      hapticRegistrationAttempts += 1
      if hapticRegistrationAttempts < 20 {
        DispatchQueue.main.async { [weak self] in
          self?.setupNativeHapticsChannel()
        }
      }
      return
    }

    didRegisterHaptics = true

    let channel = FlutterMethodChannel(
      name: "com.your_app/haptics",
      binaryMessenger: messenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "selection":
        let generator = UISelectionFeedbackGenerator()
        generator.selectionChanged()
        result(nil)
      case "rigid":
        let generator = UIImpactFeedbackGenerator(style: .rigid)
        generator.impactOccurred()
        result(nil)
      case "success":
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        result(nil)
      case "error":
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.error)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func flutterBinaryMessenger() -> FlutterBinaryMessenger? {
    if let c = window?.rootViewController as? FlutterViewController {
      return c.binaryMessenger
    }
    for scene in UIApplication.shared.connectedScenes {
      guard let windowScene = scene as? UIWindowScene else { continue }
      for w in windowScene.windows {
        if let c = w.rootViewController as? FlutterViewController {
          return c.binaryMessenger
        }
      }
    }
    return nil
  }
}
