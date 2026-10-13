import Foundation

public struct Clip: Identifiable, Equatable, Codable {
    public let id: UUID
    public let text: String
    public let source: String
    public let sourceBundleID: String?
    public let date: Date
    /// Image payloads are size-bounded by `History`; thumbnails are pre-downsampled
    /// so rendering never decodes a full-resolution image on the main thread.
    public let imageData: Data?
    public let imageThumbnail: Data?
    public let imageType: String?
    public var linkURL: String?
    public var linkTitle: String?
    public var linkImage: Data?
    public var fileURL: String?
    public var fileName: String?
    public var isFile: Bool { fileURL != nil }
    public var isLink: Bool { linkURL != nil }
    public var isImage: Bool { imageData != nil && !isFile }
    public var isImageFile: Bool {
        guard isFile else { return false }
        return ["png", "jpg", "jpeg", "heic", "tif", "tiff", "gif", "webp", "bmp"].contains(URL(fileURLWithPath: fileName ?? "").pathExtension.lowercased())
    }
    public var preview: String {
        if isImage { return "Imagen copiada" }
        if isFile { return fileName ?? "Archivo copiado" }
        return linkTitle ?? text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
    public var compactPreview: String {
        if isImage { return "Imagen copiada" }
        if isFile { return fileName ?? "Archivo copiado" }
        if isLink { return linkTitle ?? URL(string: linkURL ?? "")?.host ?? text }
        var result = ""
        var previousWasSpace = true
        for character in text {
            if character.isWhitespace {
                guard !previousWasSpace else { continue }
                result.append(" "); previousWasSpace = true
            } else {
                result.append(character); previousWasSpace = false
            }
            if result.count > 50 { return String(result.prefix(49)).trimmingCharacters(in: .whitespaces) + "…" }
        }
        return result.trimmingCharacters(in: .whitespaces)
    }
    public init(text: String, source: String, sourceBundleID: String? = nil, date: Date = Date()) {
        self.id = UUID(); self.text = text; self.source = source; self.sourceBundleID = sourceBundleID; self.date = date
        self.imageData = nil; self.imageThumbnail = nil; self.imageType = nil
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil {
            self.linkURL = url.absoluteString; self.linkTitle = nil; self.linkImage = nil
        } else {
            self.linkURL = nil; self.linkTitle = nil; self.linkImage = nil
        }
        self.fileURL = nil; self.fileName = nil
    }
    public init(imageData: Data, thumbnail: Data, imageType: String, source: String, sourceBundleID: String? = nil, date: Date = Date()) {
        self.id = UUID(); self.text = ""; self.source = source; self.sourceBundleID = sourceBundleID; self.date = date
        self.imageData = imageData; self.imageThumbnail = thumbnail; self.imageType = imageType
        self.linkURL = nil; self.linkTitle = nil; self.linkImage = nil
        self.fileURL = nil; self.fileName = nil
    }
    public init(fileURL: URL, imageData: Data? = nil, thumbnail: Data? = nil, imageType: String? = nil, source: String, sourceBundleID: String? = nil, date: Date = Date()) {
        self.id = UUID(); self.text = ""; self.source = source; self.sourceBundleID = sourceBundleID; self.date = date
        self.imageData = imageData; self.imageThumbnail = thumbnail; self.imageType = imageType
        self.linkURL = nil; self.linkTitle = nil; self.linkImage = nil
        self.fileURL = fileURL.absoluteString; self.fileName = fileURL.lastPathComponent
    }
}

public struct History: Codable {
    public private(set) var clips: [Clip] = []
    public private(set) var selectedID: UUID?
    public let capacity: Int
    public let maxBytes: Int
    /// A separate image budget keeps previews from crowding out the text history.
    public static let maximumImageCount = 12
    public static let maximumImageBytes = 8 * 1_024 * 1_024
    public static let maximumTotalImageBytes = 24 * 1_024 * 1_024
    public static let maximumLinkPreviewBytes = 1 * 1_024 * 1_024
    public var selected: Clip? { clips.first { $0.id == selectedID } ?? clips.first }
    /// Most recently copied, independent of what was picked for a previous paste.
    public var latest: Clip? { clips.first }

    public init(capacity: Int = 60, maxBytes: Int = 256_000) {
        self.capacity = max(1, capacity); self.maxBytes = max(1, maxBytes)
    }

    @discardableResult public mutating func insert(_ text: String, source: String, sourceBundleID: String? = nil) -> Bool {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= maxBytes else { return false }
        // A copy makes that text the default; picking an older clip can override it.
        if let index = clips.firstIndex(where: { $0.text == text }) {
            let clip = clips.remove(at: index)
            clips.insert(clip, at: 0); selectedID = clip.id
        } else {
            let clip = Clip(text: text, source: source, sourceBundleID: sourceBundleID)
            clips.insert(clip, at: 0); selectedID = clip.id
            if clips.count > capacity { clips.removeLast(clips.count - capacity) }
        }
        return true
    }

    @discardableResult public mutating func insertImage(_ data: Data, thumbnail: Data, imageType: String, source: String, sourceBundleID: String? = nil) -> Bool {
        guard !data.isEmpty, data.count <= Self.maximumImageBytes,
              thumbnail.count <= 1 * 1_024 * 1_024 else { return false }
        if let index = clips.firstIndex(where: { $0.imageData == data }) {
            let clip = clips.remove(at: index)
            clips.insert(clip, at: 0); selectedID = clip.id
            return true
        }
        while clips.filter({ $0.imageData != nil }).count >= Self.maximumImageCount ||
                imageByteCount + data.count + thumbnail.count > Self.maximumTotalImageBytes {
            guard let oldestImage = clips.lastIndex(where: \.isImage) else { return false }
            clips.remove(at: oldestImage)
        }
        let clip = Clip(imageData: data, thumbnail: thumbnail, imageType: imageType, source: source, sourceBundleID: sourceBundleID)
        clips.insert(clip, at: 0); selectedID = clip.id
        if clips.count > capacity { clips.removeLast(clips.count - capacity) }
        return true
    }

    @discardableResult public mutating func insertFile(_ url: URL, imageData: Data? = nil, thumbnail: Data? = nil, imageType: String? = nil, source: String, sourceBundleID: String? = nil) -> Bool {
        guard url.isFileURL else { return false }
        let canKeepPreview = clips.filter { $0.imageData != nil }.count < Self.maximumImageCount &&
            imageByteCount + (imageData?.count ?? 0) + (thumbnail?.count ?? 0) <= Self.maximumTotalImageBytes
        let clip = Clip(fileURL: url, imageData: canKeepPreview ? imageData : nil,
                        thumbnail: canKeepPreview ? thumbnail : nil,
                        imageType: canKeepPreview ? imageType : nil, source: source, sourceBundleID: sourceBundleID)
        if let index = clips.firstIndex(where: { $0.fileURL == clip.fileURL }) {
            clips.remove(at: index)
        }
        clips.insert(clip, at: 0); selectedID = clip.id
        if clips.count > capacity { clips.removeLast(clips.count - capacity) }
        return true
    }

    public mutating func updateLinkPreview(id: UUID, title: String?, image: Data?) {
        guard let index = clips.firstIndex(where: { $0.id == id }), clips[index].isLink else { return }
        clips[index].linkTitle = title
        guard let image, image.count <= Self.maximumLinkPreviewBytes,
              imageByteCount + image.count <= Self.maximumTotalImageBytes else { return }
        clips[index].linkImage = image
    }

    @discardableResult public mutating func removeOldestLinkPreview() -> Date? {
        guard let index = clips.lastIndex(where: { $0.linkImage != nil }) else { return nil }
        clips[index].linkImage = nil
        return clips[index].date
    }

    public var imageByteCount: Int {
        clips.reduce(0) { $0 + ($1.imageData?.count ?? 0) + ($1.imageThumbnail?.count ?? 0) + ($1.linkImage?.count ?? 0) }
    }

    @discardableResult public mutating func removeImages() -> Int {
        let before = clips.count
        clips.removeAll(where: \.isImage)
        if let selectedID, !clips.contains(where: { $0.id == selectedID }) {
            self.selectedID = clips.first?.id
        }
        return before - clips.count
    }

    @discardableResult public mutating func removeOldestImage() -> Clip? {
        guard let index = clips.lastIndex(where: { $0.imageData != nil }) else { return nil }
        let removed = clips.remove(at: index)
        if selectedID == removed.id { selectedID = clips.first?.id }
        return removed
    }

    public mutating func select(_ id: UUID) {
        if clips.contains(where: { $0.id == id }) { selectedID = id }
    }
    @discardableResult public mutating func remove(_ id: UUID) -> Bool {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return false }
        clips.remove(at: index)
        if selectedID == id { selectedID = clips.first?.id }
        return true
    }
    public mutating func clear() { clips.removeAll(); selectedID = nil }
}
