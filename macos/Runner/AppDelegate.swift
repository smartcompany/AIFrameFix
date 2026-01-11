import Cocoa
import FlutterMacOS
import AVFoundation

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationDidFinishLaunching(_ aNotification: Notification) {
    let controller = self.mainFlutterWindow?.contentViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "video_frame_extractor", binaryMessenger: controller.engine.binaryMessenger)
    
    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "extractFrame" {
        guard let args = call.arguments as? [String: Any],
              let videoPath = args["videoPath"] as? String,
              let positionInSeconds = args["positionInSeconds"] as? Double else {
          result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
          return
        }
        self.extractFrame(from: videoPath, at: positionInSeconds, result: result)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
    
    super.applicationDidFinishLaunching(aNotification)
  }
  
  private func extractFrame(from videoPath: String, at positionInSeconds: Double, result: @escaping FlutterResult) {
    let asset = AVAsset(url: URL(fileURLWithPath: videoPath))
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    
    let time = CMTime(seconds: positionInSeconds, preferredTimescale: 600)
    
    generator.generateCGImagesAsynchronously(forTimes: [NSValue(time: time)]) { (requestedTime, cgImage, actualTime, resultCode, error) in
      if let error = error {
        DispatchQueue.main.async {
          result(FlutterError(code: "FRAME_EXTRACTION_FAILED", message: "Failed to extract frame", details: error.localizedDescription))
        }
        return
      }
      
      guard let cgImage = cgImage else {
        DispatchQueue.main.async {
          result(FlutterError(code: "NO_IMAGE", message: "No image extracted", details: nil))
        }
        return
      }
      
      // CGImage를 PNG 데이터로 변환
      let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
      guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
        DispatchQueue.main.async {
          result(FlutterError(code: "IMAGE_CONVERSION_FAILED", message: "Failed to convert image to PNG", details: nil))
        }
        return
      }
      
      // 임시 파일에 저장
      let tempDir = FileManager.default.temporaryDirectory
      let fileName = "frame_\(UUID().uuidString).png"
      let fileURL = tempDir.appendingPathComponent(fileName)
      
      do {
        try pngData.write(to: fileURL)
        DispatchQueue.main.async {
          result(fileURL.path)
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "FILE_WRITE_FAILED", message: "Failed to write file", details: error.localizedDescription))
        }
      }
    }
  }

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }
}
