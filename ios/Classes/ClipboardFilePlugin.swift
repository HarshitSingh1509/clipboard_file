import Flutter
import UIKit

public class ClipboardFilePlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "clipboard_file",
      binaryMessenger: registrar.messenger()
    )
    let instance = ClipboardFilePlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "copyImage":
      guard let imageData = call.arguments as? FlutterStandardTypedData else {
        result(FlutterError(
          code: "INVALID_ARGUMENT",
          message: "Expected Uint8List bytes",
          details: nil
        ))
        return
      }
      ClipboardFileReader.copyImage(data: imageData.data, result: result)
    case "readImage", "readFile":
      ClipboardFileReader.readFile(from: UIPasteboard.general, completion: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
