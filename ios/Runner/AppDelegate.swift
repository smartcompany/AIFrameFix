import Flutter
import UIKit
import FirebaseCore
import UniformTypeIdentifiers

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var saveFileResult: FlutterResult?
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    FirebaseApp.configure()
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    
    // 앱이 활성화된 후 MethodChannel 설정 (이 시점에서는 FlutterViewController가 확실히 준비됨)
    setupFileSaveChannel()
  }
  
  private func setupFileSaveChannel() {
    // 이미 설정되어 있으면 다시 설정하지 않음
    if let controller = window?.rootViewController as? FlutterViewController {
      // MethodChannel이 이미 설정되어 있는지 확인하기 위해 한 번만 설정
      let fileSaveChannel = FlutterMethodChannel(
        name: "file_saver",
        binaryMessenger: controller.binaryMessenger
      )
      
      fileSaveChannel.setMethodCallHandler { [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
        guard let self = self else { return }
        
        print("DEBUG: file_saver MethodChannel 호출됨: \(call.method)")
        
        if call.method == "saveFile" {
          guard let args = call.arguments as? [String: Any],
                let filePath = args["filePath"] as? String,
                let fileName = args["fileName"] as? String else {
            print("ERROR: 잘못된 인자")
            result(FlutterError(code: "INVALID_ARGUMENTS", message: "Invalid arguments", details: nil))
            return
          }
          
          print("DEBUG: 파일 저장 요청 - 경로: \(filePath), 파일명: \(fileName)")
          self.saveFileResult = result
          self.showDocumentPicker(filePath: filePath, fileName: fileName, controller: controller)
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      
      print("DEBUG: file_saver MethodChannel 설정 완료")
    } else {
      print("WARNING: FlutterViewController를 찾을 수 없습니다")
    }
  }
  
  private func showDocumentPicker(filePath: String, fileName: String, controller: UIViewController) {
    let fileURL = URL(fileURLWithPath: filePath)
    
    // iOS 14.0 이상에서는 forExporting 사용, 그 이하에서는 url 사용
    let documentPicker: UIDocumentPickerViewController
    if #available(iOS 14.0, *) {
      documentPicker = UIDocumentPickerViewController(forExporting: [fileURL], asCopy: true)
    } else {
      // iOS 13.0에서는 url 기반 초기화 사용
      documentPicker = UIDocumentPickerViewController(url: fileURL, in: .exportToService)
    }
    
    documentPicker.delegate = self
    documentPicker.allowsMultipleSelection = false
    
    controller.present(documentPicker, animated: true)
  }
}

extension AppDelegate: UIDocumentPickerDelegate {
  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    if let result = saveFileResult {
      if let url = urls.first {
        result(url.path)
      } else {
        result(FlutterError(code: "NO_FILE_SELECTED", message: "No file selected", details: nil))
      }
      saveFileResult = nil
    }
  }
  
  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    if let result = saveFileResult {
      result(nil)
      saveFileResult = nil
    }
  }
}
