import Flutter
import UIKit
import UniformTypeIdentifiers

enum ClipboardFileReader {
  static func copyImage(data: Data, result: @escaping FlutterResult) {
    guard let image = UIImage(data: data) else {
      result(FlutterError(code: "INVALID_IMAGE", message: "Could not decode image data", details: nil))
      return
    }

    UIPasteboard.general.image = image
    result(nil)
  }

  static func readFiles(from pasteboard: UIPasteboard, completion: @escaping FlutterResult) {
    if #available(iOS 11.0, *) {
      collectImagesFromItemProviders(pasteboard.itemProviders, at: 0, accumulated: collectAllSyncImagePayloads(pasteboard)) { payloads in
        let deduped = dedupePayloads(payloads)
        completion(deduped.isEmpty ? nil : deduped)
      }
      return
    }

    let sync = dedupePayloads(collectAllSyncImagePayloads(pasteboard))
    completion(sync.isEmpty ? nil : sync)
  }

  static func readFile(from pasteboard: UIPasteboard, completion: @escaping FlutterResult) {
    readFileLegacy(from: pasteboard, completion: completion)
  }

  private static func readFileLegacy(from pasteboard: UIPasteboard, completion: @escaping FlutterResult) {
    if let urls = pasteboard.urls {
      for url in urls {
        if let payload = readFileFromURL(url, suggestedName: url.lastPathComponent) {
          completion(payload)
          return
        }
      }
    }

    // Notes and other native apps read `pasteboard.items` (multi-representation) directly.
    if let payload = readImageFromAllPasteboardItems(pasteboard) {
      completion(payload)
      return
    }

    if let payload = readImageFromRichTextPasteboard(pasteboard) {
      completion(payload)
      return
    }

    if let payload = readImageFromHtmlPasteboard(pasteboard) {
      completion(payload)
      return
    }

    if #available(iOS 11.0, *) {
      tryItemProviders(pasteboard.itemProviders, at: 0, pasteboard: pasteboard, completion: completion)
      return
    }

    finishWithPasteboardFallback(pasteboard, completion: completion)
  }

  @available(iOS 11.0, *)
  private static func tryItemProviders(
    _ providers: [NSItemProvider],
    at index: Int,
    pasteboard: UIPasteboard,
    completion: @escaping FlutterResult
  ) {
    if index >= providers.count {
      finishWithPasteboardFallback(pasteboard, completion: completion)
      return
    }

    trySingleItemProvider(providers[index]) { payload in
      if let payload {
        completion(payload)
      } else {
        tryItemProviders(providers, at: index + 1, pasteboard: pasteboard, completion: completion)
      }
    }
  }

  @available(iOS 11.0, *)
  private static func trySingleItemProvider(
    _ itemProvider: NSItemProvider,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    let suggestedName = itemProvider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)

    tryRegisteredImageTypes(itemProvider, suggestedName: suggestedName) { payload in
      if payload != nil {
        completion(payload)
        return
      }

    tryNamedFileTypes(itemProvider, suggestedName: suggestedName) { payload in
      if payload != nil {
        completion(payload)
        return
      }

      if itemProvider.canLoadObject(ofClass: UIImage.self) {
        itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
          DispatchQueue.main.async {
            if let image = object as? UIImage {
              completion(encodeUIImage(image, suggestedName: suggestedName))
            } else {
              tryImageDataRepresentations(itemProvider, suggestedName: suggestedName, completion: completion)
            }
          }
        }
        return
      }

      tryImageDataRepresentations(itemProvider, suggestedName: suggestedName, completion: completion)
    }
    }
  }

  @available(iOS 11.0, *)
  private static func tryRegisteredImageTypes(
    _ itemProvider: NSItemProvider,
    suggestedName: String?,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    let identifiers = itemProvider.registeredTypeIdentifiers.filter { isImageTypeIdentifier($0) }
    guard !identifiers.isEmpty else {
      completion(nil)
      return
    }

    tryImageDataRepresentation(
      itemProvider,
      identifiers: identifiers,
      at: 0,
      suggestedName: suggestedName,
      completion: completion
    )
  }

  private static func isImageTypeIdentifier(_ identifier: String) -> Bool {
    let lower = identifier.lowercased()
    if lower.contains("image")
      || lower.contains("png")
      || lower.contains("jpeg")
      || lower.contains("jpg")
      || lower.contains("heic")
      || lower.contains("heif")
      || lower.contains("gif")
      || lower.contains("webp")
      || lower.contains("tiff") {
      return true
    }

    if #available(iOS 14.0, *) {
      if let type = UTType(identifier), type.conforms(to: .image) {
        return true
      }
    }

    return false
  }

  @available(iOS 11.0, *)
  private static func tryNamedFileTypes(
    _ itemProvider: NSItemProvider,
    suggestedName: String?,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    guard let suggestedName, !suggestedName.isEmpty else {
      completion(nil)
      return
    }

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

    tryNamedFileType(itemProvider, identifiers: namedFileTypes, at: 0, suggestedName: suggestedName, completion: completion)
  }

  @available(iOS 11.0, *)
  private static func tryNamedFileType(
    _ itemProvider: NSItemProvider,
    identifiers: [String],
    at index: Int,
    suggestedName: String,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    if index >= identifiers.count {
      completion(nil)
      return
    }

    let identifier = identifiers[index]
    guard itemProvider.hasItemConformingToTypeIdentifier(identifier) else {
      tryNamedFileType(itemProvider, identifiers: identifiers, at: index + 1, suggestedName: suggestedName, completion: completion)
      return
    }

    if identifier == "public.plain-text" && !isDocumentFileName(suggestedName) {
      tryNamedFileType(itemProvider, identifiers: identifiers, at: index + 1, suggestedName: suggestedName, completion: completion)
      return
    }

    loadFileFromItemProvider(itemProvider, identifier: identifier) { payload in
      if payload != nil {
        completion(payload)
      } else {
        tryNamedFileType(itemProvider, identifiers: identifiers, at: index + 1, suggestedName: suggestedName, completion: completion)
      }
    }
  }

  @available(iOS 11.0, *)
  private static func tryImageDataRepresentations(
    _ itemProvider: NSItemProvider,
    suggestedName: String?,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    let imageIdentifiers = [
      "public.image",
      "public.png",
      "public.jpeg",
      "public.heic",
      "public.heif",
    ]

    tryImageDataRepresentation(
      itemProvider,
      identifiers: imageIdentifiers,
      at: 0,
      suggestedName: suggestedName,
      completion: completion
    )
  }

  @available(iOS 11.0, *)
  private static func tryImageDataRepresentation(
    _ itemProvider: NSItemProvider,
    identifiers: [String],
    at index: Int,
    suggestedName: String?,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    if index >= identifiers.count {
      tryGenericFileTypes(itemProvider, completion: completion)
      return
    }

    let identifier = identifiers[index]
    guard itemProvider.hasItemConformingToTypeIdentifier(identifier) else {
      tryImageDataRepresentation(itemProvider, identifiers: identifiers, at: index + 1, suggestedName: suggestedName, completion: completion)
      return
    }

    itemProvider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
      DispatchQueue.main.async {
        if let data = data, !data.isEmpty,
           let payload = encodeClipboardImage(
             data: data,
             sourceType: identifier,
             suggestedName: suggestedName
           ) {
          completion(payload)
        } else {
          tryImageDataRepresentation(itemProvider, identifiers: identifiers, at: index + 1, suggestedName: suggestedName, completion: completion)
        }
      }
    }
  }

  @available(iOS 11.0, *)
  private static func tryGenericFileTypes(
    _ itemProvider: NSItemProvider,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    let fileIdentifiers = [
      "public.file-url",
      "public.url",
      "public.comma-separated-values-text",
      "com.adobe.pdf",
      "org.openxmlformats.wordprocessingml.document",
      "org.openxmlformats.spreadsheetml.sheet",
      "org.openxmlformats.presentationml.presentation",
    ]

    tryGenericFileType(itemProvider, identifiers: fileIdentifiers, at: 0, completion: completion)
  }

  @available(iOS 11.0, *)
  private static func tryGenericFileType(
    _ itemProvider: NSItemProvider,
    identifiers: [String],
    at index: Int,
    completion: @escaping ([String: Any]?) -> Void
  ) {
    if index >= identifiers.count {
      completion(nil)
      return
    }

    let identifier = identifiers[index]
    guard itemProvider.hasItemConformingToTypeIdentifier(identifier) else {
      tryGenericFileType(itemProvider, identifiers: identifiers, at: index + 1, completion: completion)
      return
    }

    loadFileFromItemProvider(itemProvider, identifier: identifier) { payload in
      if payload != nil {
        completion(payload)
      } else {
        tryGenericFileType(itemProvider, identifiers: identifiers, at: index + 1, completion: completion)
      }
    }
  }

  private static func finishWithPasteboardFallback(_ pasteboard: UIPasteboard, completion: @escaping FlutterResult) {
    if let payload = readImageFromPasteboard(pasteboard) {
      completion(payload)
      return
    }

    completion(nil)
  }

  /// Walk every pasteboard item/representation (same sources native UITextView/Notes use).
  private static func readImageFromAllPasteboardItems(_ pasteboard: UIPasteboard) -> [String: Any]? {
    if let image = pasteboard.image, let payload = encodeUIImage(image) {
      return payload
    }

    for item in pasteboard.items {
      for (type, value) in item {
        guard let typeId = type as? String else { continue }

        if isPlainTextTypeIdentifier(typeId) {
          if let text = value as? String, isImagePlaceholderText(text) {
            continue
          }
          continue
        }

        if let image = value as? UIImage, let payload = encodeUIImage(image) {
          return payload
        }

        if let url = value as? URL, let payload = readImagePayloadFromFileURL(url) {
          return payload
        }

        guard let data = value as? Data, !data.isEmpty else { continue }

        if typeId.lowercased().contains("html"),
           let html = String(data: data, encoding: .utf8),
           let payload = decodeImagePayloadFromHtml(html) {
          return payload
        }

        if typeId.lowercased().contains("rtf"),
           let payload = extractImageFromRichTextData(data, typeId: typeId) {
          return payload
        }

        if let payload = encodeClipboardImage(data: data, sourceType: typeId) {
          return payload
        }
      }
    }

    return nil
  }

  private static func isPlainTextTypeIdentifier(_ typeId: String) -> Bool {
    let lower = typeId.lowercased()
    return lower.contains("plain-text")
      || lower == "public.utf8-plain-text"
      || lower == "nsstringpboardtype"
  }

  private static func readImagePayloadFromFileURL(_ url: URL) -> [String: Any]? {
    guard let payload = readFileFromURL(url, suggestedName: url.lastPathComponent),
          let ext = payload["extension"] as? String else {
      return nil
    }
    let imageExtensions = ["png", "jpeg", "jpg", "heic", "heif", "gif", "webp"]
    return imageExtensions.contains(ext) ? payload : nil
  }

  private static func readImageFromRichTextPasteboard(_ pasteboard: UIPasteboard) -> [String: Any]? {
    let richTypes = [
      "public.rtfd",
      "com.apple.flat-rtfd",
      "public.rtf",
      "com.apple.richtext",
    ]

    for type in richTypes {
      guard let data = pasteboard.data(forPasteboardType: type), !data.isEmpty else { continue }
      if let payload = extractImageFromRichTextData(data, typeId: type) {
        return payload
      }
    }

    return nil
  }

  private static func extractImageFromRichTextData(_ data: Data, typeId: String) -> [String: Any]? {
    extractAllImagesFromRichTextData(data, typeId: typeId).first
  }

  private static func extractAllImagesFromRichTextData(_ data: Data, typeId: String) -> [[String: Any]] {
    let lower = typeId.lowercased()
    let documentType: NSAttributedString.DocumentType = lower.contains("rtfd")
      ? .rtfd
      : .rtf

    let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
      .documentType: documentType,
    ]

    guard let attributed = try? NSAttributedString(
      data: data,
      options: options,
      documentAttributes: nil
    ) else {
      return []
    }

    var payloads: [[String: Any]] = []
    let fullRange = NSRange(location: 0, length: attributed.length)
    attributed.enumerateAttribute(.attachment, in: fullRange) { value, _, _ in
      guard let attachment = value as? NSTextAttachment else { return }

      if let image = attachment.image, let payload = encodeUIImage(image) {
        payloads.append(payload)
        return
      }

      if let wrapper = attachment.fileWrapper, let bytes = wrapper.regularFileContents, !bytes.isEmpty,
         let payload = encodeClipboardImage(data: bytes, sourceType: "public.png") {
        payloads.append(payload)
      }
    }

    return payloads
  }

  @available(iOS 11.0, *)
  private static func loadFileFromItemProvider(
    _ itemProvider: NSItemProvider,
    identifier: String,
    completion: @escaping ([String: Any]?) -> Void
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

    if let text = String(data: data, encoding: .utf8), isImagePlaceholderText(text) {
      return nil
    }

    let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
    let suggestedExt = (suggested as NSString?)?.pathExtension.lowercased() ?? ""
    let urlExt = url.pathExtension.lowercased()
    let extensionValue = detectExtension(from: data)
      ?? (!suggestedExt.isEmpty ? suggestedExt : nil)
      ?? (!urlExt.isEmpty ? urlExt : nil)
      ?? extensionForTypeIdentifier(typeIdentifier)
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

  private static func isImagePlaceholderText(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.caseInsensitiveCompare("Image") == .orderedSame {
      return true
    }
    let pattern = "^\\s*(\\[Image\\]\\s*)+\\s*$"
    return trimmed.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
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

  private static func readImageFromHtmlPasteboard(_ pasteboard: UIPasteboard) -> [String: Any]? {
    let htmlTypes = [
      "public.html",
      "Apple HTML pasteboard type",
    ]

    for type in htmlTypes {
      guard let data = pasteboard.data(forPasteboardType: type), !data.isEmpty else {
        continue
      }
      let html = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .utf16)
        ?? String(decoding: data, as: UTF8.self)
      if let payload = decodeImagePayloadFromHtml(html) {
        return payload
      }
    }

    if let string = pasteboard.string, string.contains("<") {
      return decodeImagePayloadFromHtml(string)
    }

    return nil
  }

  private static func decodeImagePayloadFromHtml(_ html: String) -> [String: Any]? {
    let pattern = "data:image/(png|jpeg|jpg|gif|webp);base64,([A-Za-z0-9+/=\\s]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return nil
    }
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    guard let match = regex.firstMatch(in: html, options: [], range: range),
          match.numberOfRanges >= 3,
          let subtypeRange = Range(match.range(at: 1), in: html),
          let base64Range = Range(match.range(at: 2), in: html) else {
      return nil
    }

    let subtype = html[subtypeRange].lowercased()
    let base64 = html[base64Range].replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
    guard let data = Data(base64Encoded: base64), !data.isEmpty else {
      return nil
    }

    let ext: String
    switch subtype {
    case "png":
      ext = "png"
    case "jpeg", "jpg":
      ext = "jpeg"
    case "gif":
      ext = "gif"
    case "webp":
      ext = "webp"
    default:
      return nil
    }

    return makeImagePayload(bytes: data, extension: ext, suggestedName: nil)
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
    if let detected = detectExtension(from: data) {
      return makeImagePayload(bytes: data, extension: detected, suggestedName: suggestedName)
    }

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
    let resolvedExt = detectExtension(from: bytes) ?? ext

    var payload: [String: Any] = [
      "bytes": FlutterStandardTypedData(bytes: bytes),
      "extension": resolvedExt,
    ]

    if let suggested = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines),
       !suggested.isEmpty {
      if suggested.contains(".") {
        let base = (suggested as NSString).deletingPathExtension
        payload["fileName"] = "\(base).\(resolvedExt)"
      } else {
        payload["fileName"] = "\(suggested).\(resolvedExt)"
      }
    }

    return payload
  }

  private static func collectAllSyncImagePayloads(_ pasteboard: UIPasteboard) -> [[String: Any]] {
    var payloads: [[String: Any]] = []

    if let urls = pasteboard.urls {
      for url in urls {
        if let payload = readImagePayloadFromFileURL(url) {
          payloads.append(payload)
        }
      }
    }

    payloads.append(contentsOf: collectAllFromPasteboardItems(pasteboard))
    payloads.append(contentsOf: collectAllFromHtmlPasteboard(pasteboard))
    payloads.append(contentsOf: collectAllFromRichTextPasteboard(pasteboard))

    return payloads
  }

  private static func collectAllFromPasteboardItems(_ pasteboard: UIPasteboard) -> [[String: Any]] {
    var payloads: [[String: Any]] = []
    for item in pasteboard.items {
      for (type, value) in item {
        guard let typeId = type as? String else { continue }
        if isPlainTextTypeIdentifier(typeId) { continue }

        if let image = value as? UIImage, let payload = encodeUIImage(image) {
          payloads.append(payload)
          continue
        }
        if let url = value as? URL, let payload = readImagePayloadFromFileURL(url) {
          payloads.append(payload)
          continue
        }
        guard let data = value as? Data, !data.isEmpty else { continue }

        if typeId.lowercased().contains("html"),
           let html = String(data: data, encoding: .utf8) {
          payloads.append(contentsOf: decodeAllImagePayloadsFromHtml(html))
          continue
        }
        if typeId.lowercased().contains("rtf") {
          payloads.append(contentsOf: extractAllImagesFromRichTextData(data, typeId: typeId))
          continue
        }
        if let payload = encodeClipboardImage(data: data, sourceType: typeId) {
          payloads.append(payload)
        }
      }
    }
    return payloads
  }

  private static func collectAllFromHtmlPasteboard(_ pasteboard: UIPasteboard) -> [[String: Any]] {
    var payloads: [[String: Any]] = []
    let htmlTypes = ["public.html", "Apple HTML pasteboard type"]

    for item in pasteboard.items {
      for (type, value) in item {
        guard let typeId = type as? String else { continue }
        guard htmlTypes.contains(where: { typeId == $0 || typeId.lowercased().contains("html") }) else {
          continue
        }
        let html: String?
        if let data = value as? Data, !data.isEmpty {
          html = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(decoding: data, as: UTF8.self)
        } else if let text = value as? String {
          html = text
        } else {
          html = nil
        }
        if let html {
          payloads.append(contentsOf: decodeAllImagePayloadsFromHtml(html))
        }
      }
    }

    for type in htmlTypes {
      guard let data = pasteboard.data(forPasteboardType: type), !data.isEmpty else { continue }
      let html = String(data: data, encoding: .utf8)
        ?? String(data: data, encoding: .utf16)
        ?? String(decoding: data, as: UTF8.self)
      payloads.append(contentsOf: decodeAllImagePayloadsFromHtml(html))
    }
    if let string = pasteboard.string, string.contains("<") {
      payloads.append(contentsOf: decodeAllImagePayloadsFromHtml(string))
    }
    return payloads
  }

  private static func collectAllFromRichTextPasteboard(_ pasteboard: UIPasteboard) -> [[String: Any]] {
    var payloads: [[String: Any]] = []
    for item in pasteboard.items {
      for (type, value) in item {
        guard let typeId = type as? String, typeId.lowercased().contains("rtf") else { continue }
        guard let data = value as? Data, !data.isEmpty else { continue }
        payloads.append(contentsOf: extractAllImagesFromRichTextData(data, typeId: typeId))
      }
    }

    let richTypes = ["public.rtfd", "com.apple.flat-rtfd", "public.rtf", "com.apple.richtext"]
    for type in richTypes {
      guard let data = pasteboard.data(forPasteboardType: type), !data.isEmpty else { continue }
      payloads.append(contentsOf: extractAllImagesFromRichTextData(data, typeId: type))
    }
    return payloads
  }

  private static func decodeAllImagePayloadsFromHtml(_ html: String) -> [[String: Any]] {
    let pattern = "data:image/(png|jpeg|jpg|gif|webp);base64,([A-Za-z0-9+/=\\s]+)"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
      return []
    }
    let range = NSRange(html.startIndex..<html.endIndex, in: html)
    var payloads: [[String: Any]] = []
    regex.enumerateMatches(in: html, options: [], range: range) { match, _, _ in
      guard let match,
            match.numberOfRanges >= 3,
            let subtypeRange = Range(match.range(at: 1), in: html),
            let base64Range = Range(match.range(at: 2), in: html) else { return }

      let subtype = html[subtypeRange].lowercased()
      let base64 = html[base64Range].replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
      guard let data = Data(base64Encoded: base64), !data.isEmpty else { return }

      let ext: String
      switch subtype {
      case "png": ext = "png"
      case "jpeg", "jpg": ext = "jpeg"
      case "gif": ext = "gif"
      case "webp": ext = "webp"
      default: return
      }

      payloads.append(makeImagePayload(bytes: data, extension: ext, suggestedName: nil))
    }
    return payloads
  }

  @available(iOS 11.0, *)
  private static func collectImagesFromItemProviders(
    _ providers: [NSItemProvider],
    at index: Int,
    accumulated: [[String: Any]],
    completion: @escaping ([[String: Any]]) -> Void
  ) {
    if index >= providers.count {
      completion(accumulated)
      return
    }

    collectAllImagesFromItemProvider(providers[index]) { providerPayloads in
      var next = accumulated
      next.append(contentsOf: providerPayloads.filter(isImagePayload))
      collectImagesFromItemProviders(providers, at: index + 1, accumulated: next, completion: completion)
    }
  }

  @available(iOS 11.0, *)
  private static func collectAllImagesFromItemProvider(
    _ itemProvider: NSItemProvider,
    completion: @escaping ([[String: Any]]) -> Void
  ) {
    let imageIds = itemProvider.registeredTypeIdentifiers.filter { isImageTypeIdentifier($0) }
    guard !imageIds.isEmpty else {
      trySingleItemProvider(itemProvider) { payload in
        if let payload, isImagePayload(payload) {
          completion([payload])
        } else {
          completion([])
        }
      }
      return
    }

    collectImagePayloadsForTypeIds(
      itemProvider,
      identifiers: imageIds,
      at: 0,
      accumulated: [],
      completion: completion
    )
  }

  @available(iOS 11.0, *)
  private static func collectImagePayloadsForTypeIds(
    _ itemProvider: NSItemProvider,
    identifiers: [String],
    at index: Int,
    accumulated: [[String: Any]],
    completion: @escaping ([[String: Any]]) -> Void
  ) {
    if index >= identifiers.count {
      if accumulated.isEmpty {
        trySingleItemProvider(itemProvider) { payload in
          completion(payload.flatMap { isImagePayload($0) ? [$0] : [] } ?? [])
        }
      } else {
        completion(accumulated)
      }
      return
    }

    let identifier = identifiers[index]
    guard itemProvider.hasItemConformingToTypeIdentifier(identifier) else {
      collectImagePayloadsForTypeIds(
        itemProvider,
        identifiers: identifiers,
        at: index + 1,
        accumulated: accumulated,
        completion: completion
      )
      return
    }

    itemProvider.loadDataRepresentation(forTypeIdentifier: identifier) { data, _ in
      DispatchQueue.main.async {
        var next = accumulated
        if let data, !data.isEmpty,
           let payload = encodeClipboardImage(
             data: data,
             sourceType: identifier,
             suggestedName: itemProvider.suggestedName
           ) {
          next.append(payload)
        }
        collectImagePayloadsForTypeIds(
          itemProvider,
          identifiers: identifiers,
          at: index + 1,
          accumulated: next,
          completion: completion
        )
      }
    }
  }

  private static func isImagePayload(_ payload: [String: Any]) -> Bool {
    guard let ext = payload["extension"] as? String else { return false }
    return ["png", "jpeg", "jpg", "gif", "webp", "heic", "heif"].contains(ext.lowercased())
  }

  private static func dedupePayloads(_ payloads: [[String: Any]]) -> [[String: Any]] {
    var seen = Set<String>()
    var unique: [[String: Any]] = []
    for payload in payloads {
      guard let fingerprint = payloadFingerprint(payload), !seen.contains(fingerprint) else { continue }
      seen.insert(fingerprint)
      unique.append(payload)
    }
    return unique
  }

  private static func payloadFingerprint(_ payload: [String: Any]) -> String? {
    guard let typed = payload["bytes"] as? FlutterStandardTypedData else { return nil }
    let data = typed.data
    let prefix = data.prefix(32).map { String(format: "%02x", $0) }.joined()
    return "\(data.count)-\(prefix)"
  }

  static func readPasteDiagnostics(from pasteboard: UIPasteboard) -> [String: Any] {
    var itemTypeKeys: [[String]] = []
    for item in pasteboard.items {
      itemTypeKeys.append(item.keys.compactMap { $0 as? String })
    }

    let plain = pasteboard.string ?? ""
    let placeholderPattern = "\\[Image\\]"
    let placeholderCount: Int = {
      guard let regex = try? NSRegularExpression(pattern: placeholderPattern, options: [.caseInsensitive]) else {
        return 0
      }
      let range = NSRange(plain.startIndex..<plain.endIndex, in: plain)
      return regex.numberOfMatches(in: plain, options: [], range: range)
    }()

    return [
      "itemsCount": pasteboard.items.count,
      "providerCount": pasteboard.itemProviders.count,
      "itemTypeKeys": itemTypeKeys,
      "plainTextPreview": String(plain.prefix(160)),
      "placeholderCount": placeholderCount > 0
        ? placeholderCount
        : (plain.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Image") == .orderedSame ? 1 : 0),
    ]
  }
}
