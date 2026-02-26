import Flutter
import UIKit

public class MobileMcpPlugin: NSObject, FlutterPlugin {
  private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
  private var lastSourceApplication: String? = nil

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "mobile_mcp/lifecycle", binaryMessenger: registrar.messenger())
    let instance = MobileMcpPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addApplicationDelegate(instance)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "acquireBackgroundLock":
      if backgroundTaskId == .invalid {
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "MobileMcp:BackgroundLock") {
          UIApplication.shared.endBackgroundTask(self.backgroundTaskId)
          self.backgroundTaskId = .invalid
        }
      }
      result(true)
    case "releaseBackgroundLock":
      if backgroundTaskId != .invalid {
        UIApplication.shared.endBackgroundTask(backgroundTaskId)
        backgroundTaskId = .invalid
      }
      result(true)
    case "getCallingPackage":
      // On iOS we call it sourceApplication
      result(lastSourceApplication)
    case "isWindowObscured":
      // iOS is less susceptible to overlay attacks than Android
      result(false)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func application(_ application: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    lastSourceApplication = options[.sourceApplication] as? String
    return false // Let other handlers (like app_links) handle it
  }

  public func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([Any]) -> Void) -> Bool {
    if userActivity.activityType == NSUserActivityTypeBrowsingWeb {
      // Universal Link was used.
      // iOS doesn't provide sourceApplication for Universal Links for privacy.
      // We set a marker to indicate it's a verified transport.
      lastSourceApplication = "Verified (Universal Link)"
    }
    return false
  }
}
