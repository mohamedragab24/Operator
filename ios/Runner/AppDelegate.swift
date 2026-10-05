import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {

  private var screenProtectionEventSink: FlutterEventSink?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController

    let eventChannel = FlutterEventChannel(
      name: "masar/screen_protection",
      binaryMessenger: controller.binaryMessenger
    )
    eventChannel.setStreamHandler(ScreenProtectionStreamHandler(delegate: self))

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func setEventSink(_ sink: FlutterEventSink?) {
    self.screenProtectionEventSink = sink
  }

  func sendScreenEvent(type: String, active: Bool) {
    screenProtectionEventSink?(["type": type, "active": active])
  }
}

/// Wires two pieces of iOS-native detection into the event channel:
///  1) UIScreen.capturedDidChangeNotification — fires when screen
///     recording / AirPlay mirroring / QuickTime screen capture starts
///     or stops. This is the closest thing iOS offers to knowing a
///     recording is happening, and it's the only *reliable* signal.
///  2) UIApplication.userDidTakeScreenshotNotification — fires AFTER a
///     screenshot is taken. It cannot be prevented (no such API exists
///     on iOS), only reacted to.
class ScreenProtectionStreamHandler: NSObject, FlutterStreamHandler {
  weak var delegate: AppDelegate?

  init(delegate: AppDelegate) {
    self.delegate = delegate
  }

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    delegate?.setEventSink(events)

    NotificationCenter.default.addObserver(
      self, selector: #selector(recordingChanged),
      name: UIScreen.capturedDidChangeNotification, object: nil
    )
    NotificationCenter.default.addObserver(
      self, selector: #selector(screenshotTaken),
      name: UIApplication.userDidTakeScreenshotNotification, object: nil
    )

    // Report the current state immediately in case recording already
    // started before the listener attached (e.g. Control Center capture
    // began right as the app opened).
    recordingChanged()

    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    NotificationCenter.default.removeObserver(self)
    delegate?.setEventSink(nil)
    return nil
  }

  @objc private func recordingChanged() {
    let isCaptured = UIScreen.main.isCaptured
    delegate?.sendScreenEvent(type: "recording", active: isCaptured)
  }

  @objc private func screenshotTaken() {
    delegate?.sendScreenEvent(type: "screenshot", active: true)
  }
}
