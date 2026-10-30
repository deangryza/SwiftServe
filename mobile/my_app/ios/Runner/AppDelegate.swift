import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "swiftserve/notification_settings", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        guard call.method == "open" else { result(FlutterMethodNotImplemented); return }
        if let url = URL(string: UIApplication.openSettingsURLString) {
          UIApplication.shared.open(url, options: [:]) { opened in result(opened) }
        } else { result(false) }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
