import Flutter
import UIKit

enum ClipboardFileReader {
  static func copyImage(data: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: data) else {
      result(FlutterError(code: "INVALID_IMAGE", message: "Could not decode image data", details: nil))
      return
    }

    UIPasteboard.general.image = image
    result(nil)
  }

  static func readFile(from pasteboard: UIPasteboard, completion: @escaping FlutterResult) {
    if let urls = pasteboard.urls {
      for url in urls {
        if let payload = readFileFromURL(url, suggestedName: url.lastPathComponent) {
          completion(payload)
          return
        }
      }
    }

    if #available(iOS 11.0, *) {
      for itemProvider in pasteboard.itemProviders {
        let suggestedName = itemProvider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)

        if let suggestedName, !suggestedName.isEmpty {
          let namedFileTypes = [
            "public.file-url",
            "public.url",
            "public.comma-separated-values-text",
            "public.plain-text",
            "public.png",
            "public.jpeg",
            "public.heic",
            "public.heif",
          ]
          for identifier in namedFileTypes where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
            if identifier == "public.plain-text" && !isDocumentFileName(suggestedName) {
              continue
            }
            loadFileFromItemProvider(itemProvider, identifier: identifier, completion: completion)
            return
          }
        }

        if itemProvider.canLoadObject(ofClass: UIImage.self) {
          itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
            DispatchQueue.main.async {
              guard let image = object as? UIImage else {
                completion(nil)
                return
              }
              completion(encodeUIImage(image, suggestedName: suggestedName))
            }
          }
          return
        }

        let imageIdentifiers = [
          "public.image",
          "public.png",
          "public.jpeg",
          "public.heic",
          "public.heif",
        ]

        for identifier in imageIdentifiers where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
          itemProvider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
            DispatchQueue.main.async {
              guard let data = data, !data.isEmpty,
                    let payload = encodeClipboardImage(
                      data: data,
                      sourceType: identifier,
                      suggestedName: suggestedName
                    ) else {
                completion(nil)
                return
              }
              completion(payload)
            }
          }
          return
        }

        let fileIdentifiers = [
          "public.file-url",
          "public.url",
          "public.comma-separated-values-text",
          "com.adobe.pdf",
          "org.openxmlformats.wordprocessingml.document",
          "org.openxmlformats.spreadsheetml.sheet",
          "org.openxmlformats.presentationml.presentation",
        ]

        for identifier in fileIdentifiers where itemProvider.hasItemConformingToTypeIdentifier(identifier) {
          loadFileFromItemProvider(itemProvider, identifier: identifier, completion: completion)
          return
        }
      }
    }

    if let payload = readImageFromPasteboard(pasteboard) {
      completion(payload)
      return
    }

    completion(nil)
  }

  @available(iOS 11.0, *)
  private static func loadFileFromItemProvider(
    _ itemProvider: NSItemProvider,
    identifier: String,
    completion: @escaping FlutterResult
  ) {
    let suggestedName = itemProvider.suggestedName
    itemProvider.loadFileRepresentation(forTypeIdentifier: identifier) { url, _ in
      DispatchQueue.main.async {
        guard let url = url,
              let payload = readFileFromURL(
                url,
                suggestedName: suggestedName,
                typeIdentifier: identifier
              ) else {
          completion(nil)
          return
        }
        completion(payload)
      }
    }
  }

  private static func readFileFromURL(
    _ url: URL,
    suggestedName: String?,
    typeIdentifier: String? = nil
  ) -> [String: Any]? {
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
      if didAccess {
        url.stopAccessingSecurityScopedResource()
      }
    }

    guard let data = try? Data(contentsOf: url), !data.isEmpty else {
      return nil
    }

    let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let suggestedExt = (suggested as NSString?)?.pathExtension.lowercased() ?? ""
    let urlExt = url.pathExtension.lowercased()
    let extensionValue = !suggestedExt.isEmpty
      ? suggestedExt
      : (!urlExt.isEmpty
        ? urlExt
        : (detectExtension(from: data) ?? extensionForTypeIdentifier(typeIdentifier)))
    guard let extensionValue, !extensionValue.isEmpty else {
      return nil
    }

    var payload: [String: Any] = [
      "bytes": FlutterStandardTypedData(bytes: data),
      "extension": extensionValue,
    ]

    if let suggested, !suggested.isEmpty {
      payload["fileName"] = suggested.contains(".") ? suggested : "\(suggested).\(extensionValue)"
    } else if url.lastPathComponent.contains(".") {
      payload["fileName"] = url.lastPathComponent
    }

    return payload
  }

  private static func isDocumentFileName(_ fileName: String) -> Bool {
    let ext = (fileName as NSString).pathExtension.lowercased()
    guard !ext.isEmpty else { return false }
    return [
      "csv", "txt", "pdf", "doc", "docx", "ppt", "pptx", "xls", "xlsx", "png", "jpg", "jpeg",
    ].contains(ext)
  }

  private static func extensionForTypeIdentifier(_ identifier: String?) -> String? {
    switch identifier {
    case "com.adobe.pdf":
      return "pdf"
    case "org.openxmlformats.wordprocessingml.document":
      return "docx"
    case "org.openxmlformats.spreadsheetml.sheet":
      return "xlsx"
    case "org.openxmlformats.presentationml.presentation":
      return "pptx"
    case "public.png":
      return "png"
    case "public.jpeg", "public.jpg":
      return "jpeg"
    case "public.heic", "public.heif":
      return "heic"
    case "public.comma-separated-values-text":
      return "csv"
    case "public.plain-text":
      return "txt"
    default:
      return nil
    }
  }

  private static func detectExtension(from data: Data) -> String? {
    if data.starts(with: [0x25, 0x50, 0x44, 0x46]) {
      return "pdf"
    }
    if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) {
      return "png"
    }
    if data.count >= 2 && data[0] == 0xFF && data[1] == 0xD8 {
      return "jpeg"
    }
    return nil
  }

  private static func readImageFromPasteboard(_ pasteboard: UIPasteboard) -> [String: Any]? {
    let imageTypes = [
      "public.png",
      "public.jpeg",
      "public.jpg",
      "public.image",
      "public.tiff",
      "com.compuserve.gif",
      "com.apple.uikit.image",
      "public.heic",
      "public.heif",
    ]

    for type in imageTypes {
      guard let data = pasteboard.data(forPasteboardType: type), !data.isEmpty else {
        continue
      }
      if let payload = encodeClipboardImage(data: data, sourceType: type) {
        return payload
      }
    }

    if let image = pasteboard.image {
      return encodeUIImage(image)
    }

    return nil
  }

  private static func encodeUIImage(_ image: UIImage, suggestedName: String? = nil) -> [String: Any]? {
    if let pngData = image.pngData() {
      return makeImagePayload(bytes: pngData, extension: "png", suggestedName: suggestedName)
    }
    if let jpegData = image.jpegData(compressionQuality: 0.92) {
      return makeImagePayload(bytes: jpegData, extension: "jpeg", suggestedName: suggestedName)
    }
    return nil
  }

  private static func encodeClipboardImage(
    data: Data,
    sourceType: String,
    suggestedName: String? = nil
  ) -> [String: Any]? {
    if sourceType == "public.png" {
      return makeImagePayload(bytes: data, extension: "png", suggestedName: suggestedName)
    }

    if sourceType == "public.jpeg" || sourceType == "public.jpg" {
      return makeImagePayload(bytes: data, extension: "jpeg", suggestedName: suggestedName)
    }

    guard let image = UIImage(data: data) else {
      return nil
    }

    if sourceType == "com.compuserve.gif", let pngData = image.pngData() {
      return makeImagePayload(bytes: pngData, extension: "png", suggestedName: suggestedName)
    }

    if let jpegData = image.jpegData(compressionQuality: 0.92) {
      return makeImagePayload(bytes: jpegData, extension: "jpeg", suggestedName: suggestedName)
    }

    if let pngData = image.pngData() {
      return makeImagePayload(bytes: pngData, extension: "png", suggestedName: suggestedName)
    }

    return nil
  }

  private static func makeImagePayload(
    bytes: Data,
    extension ext: String,
    suggestedName: String?
  ) -> [String: Any] {
    var payload: [String: Any] = [
      "bytes": FlutterStandardTypedData(bytes: bytes),
      "extension": ext,
    ]

    if let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !suggested.isEmpty {
      payload["fileName"] = suggested.contains(".") ? suggested : "\(suggested).\(ext)"
    }

    return payload
  }
}
