import AppKit
import ImageIO
import LinkPresentation
import UniformTypeIdentifiers
#if canImport(ClipboardCore)
import ClipboardCore
#endif
import Combine
import AudioToolbox

private struct ClipboardHistoryArchive: Codable {
    var normal: History
    var ghost: History
    private static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Paste Shifter", isDirectory: true)
            .appendingPathComponent("ClipboardHistory.json")
    }
    static func load() -> Self {
        guard UserDefaults.standard.object(forKey: "keepClipboardHistory") as? Bool ?? true else {
            return Self(normal: History(), ghost: History())
        }
        guard let data = try? Data(contentsOf: fileURL),
              let archive = try? JSONDecoder().decode(Self.self, from: data) else {
            return Self(normal: History(), ghost: History())
        }
        return archive
    }
    func save() {
        guard UserDefaults.standard.object(forKey: "keepClipboardHistory") as? Bool ?? true else {
            try? FileManager.default.removeItem(at: Self.fileURL)
            return
        }
        let destination = Self.fileURL
        guard let data = try? JSONEncoder().encode(self) else { return }
        try? FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: destination.deletingLastPathComponent().path)
        try? data.write(to: destination, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
    }
}

enum ClipboardSpace: String, CaseIterable, Identifiable {
    case normal = "Normal", ghost = "Fantasma", flash = "Flash", privateSession = "Privado"
    var id: String { rawValue }
    var icon: String {
        switch self { case .normal: "doc.on.clipboard"; case .ghost: "ghost.fill"; case .flash: "bolt.fill"; case .privateSession: "lock.fill" }
    }
}

final class ClipboardStore: ObservableObject {
    private static let savedHistory = ClipboardHistoryArchive.load()
    private static let maximumSourceImageBytes = 32 * 1_024 * 1_024
    private struct ImageCapture {
        let data: Data
        let type: String
        let source: String
        let sourceBundleID: String?
        let changeCount: Int
        let generation: Int
        let space: ClipboardSpace
        let notify: Bool
    }
    private struct ProcessedImage {
        let data: Data
        let thumbnail: Data
        let type: String
    }
    private struct FileCapture {
        let url: URL
        let source: String
        let sourceBundleID: String?
        let changeCount: Int
        let generation: Int
        let space: ClipboardSpace
        let notify: Bool
    }
    @Published private(set) var history = ClipboardStore.savedHistory.normal { didSet { persistHistory() } }
    @Published private(set) var ghostHistory = ClipboardStore.savedHistory.ghost { didSet { persistHistory() } }
    @Published private(set) var privateHistory = History()
    @Published private(set) var flashHistory = History()
    @Published var space: ClipboardSpace = .normal
    @Published private(set) var flashExpiresAt: Date?
    @Published var privateUnlocked = false
    @Published var privateError: String?
    @Published var paused = false
    @Published var globalScrollUnavailable = false
    @Published var keepClipboardHistory = UserDefaults.standard.object(forKey: "keepClipboardHistory") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(keepClipboardHistory, forKey: "keepClipboardHistory")
            persistHistory()
        }
    }
    @Published var showActivity = UserDefaults.standard.object(forKey: "showActivity") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showActivity, forKey: "showActivity") }
    }
    @Published var privateSoundEnabled = UserDefaults.standard.object(forKey: "privateSoundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(privateSoundEnabled, forKey: "privateSoundEnabled") }
    }
    @Published var flashSoundEnabled = UserDefaults.standard.object(forKey: "flashSoundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(flashSoundEnabled, forKey: "flashSoundEnabled") }
    }
    @Published var ghostSoundEnabled = UserDefaults.standard.object(forKey: "ghostSoundEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(ghostSoundEnabled, forKey: "ghostSoundEnabled") }
    }
    @Published var showFlashTimer = UserDefaults.standard.object(forKey: "showFlashTimer") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showFlashTimer, forKey: "showFlashTimer") }
    }
    @Published var showScreenshots = UserDefaults.standard.object(forKey: "showScreenshots") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showScreenshots, forKey: "showScreenshots")
            if !filtered.contains(where: { $0.id == highlightedID }) { highlightedID = filtered.first?.id }
        }
    }
    @Published var captureScreenshots = UserDefaults.standard.object(forKey: "captureScreenshots") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(captureScreenshots, forKey: "captureScreenshots")
            imageCaptureGeneration += 1
            pendingImageCapture = nil
        }
    }
    var onCopy: (() -> Void)?
    var onNormalClipInserted: ((String) -> Void)?
    var onTick: (() -> Void)?
    @Published var query = "" {
        didSet {
            if !filtered.contains(where: { $0.id == highlightedID }) { highlightedID = filtered.first?.id }
        }
    }
    @Published var searchExpanded = false
    @Published var searchFocused = false
    @Published var highlightedID: UUID?
    private var timer: Timer?
    private var changeCount = -1
    private var demo = false
    private let vault = PrivateVault()
    private var flashTimer: Timer?
    private var flashText: String?
    private var flashClipboardChangeCount: Int?
    private var privateUnlockInProgress = false
    private var privateUnlockGeneration = 0
    private var savePrivateAfterUnlock = false
    private let imageProcessingQueue = DispatchQueue(label: "com.pasteshifter.image-processing", qos: .utility)
    private var imageCaptureGeneration = 0
    private var imageCaptureInFlight = false
    private var pendingImageCapture: ImageCapture?
    private var pendingLinkProviders: [UUID: LPMetadataProvider] = [:]
    private let historyPersistenceQueue = DispatchQueue(label: "com.pasteshifter.history-persistence", qos: .utility)
    var filtered: [Clip] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let clips = visibleHistory.clips.filter { showScreenshots || !$0.isImage }
        return query.isEmpty ? clips : clips.filter {
            $0.text.localizedCaseInsensitiveContains(query) || $0.source.localizedCaseInsensitiveContains(query) ||
                ($0.fileName?.localizedCaseInsensitiveContains(query) ?? false) ||
                ($0.linkTitle?.localizedCaseInsensitiveContains(query) ?? false) ||
                ($0.linkURL?.localizedCaseInsensitiveContains(query) ?? false) ||
                (($0.isImage || ($0.isFile && $0.imageData != nil)) && ["imagen", "captura", "screenshot", "image", "foto"].contains(where: { $0.localizedCaseInsensitiveContains(query) }))
        }
    }
    var highlighted: Clip? { filtered.first { $0.id == highlightedID } ?? filtered.first }
    var latestVisibleClip: Clip? { visibleHistory.clips.first { showScreenshots || !$0.isImage } }
    var visibleHistory: History {
        switch space {
        case .normal: history
        case .ghost: ghostHistory
        case .flash: flashHistory
        case .privateSession: privateHistory
        }
    }
    var screenshotCount: Int {
        history.clips.filter(\.isImage).count + ghostHistory.clips.filter(\.isImage).count
    }

    func start() {
        capture(notify: false)
        let timer = Timer(timeInterval: 0.3, repeats: true) { [weak self] _ in
            self?.onTick?()
            self?.capture()
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // Isolated visual QA: never reads or writes the real clipboard.
    func historyDemo() {
        demo = true
        for (text, source) in [
            ("Hola, ¿cómo estás? Te comparto la propuesta actualizada.", "Mail"),
            ("Un espacio para las ideas que todavía quieres tener a mano.", "Notas"),
            ("Revisar el diseño\nAjustar los últimos detalles\nCompartir la primera versión", "Recordatorios"),
            ("https://example.com/proyecto", "Safari"),
            ("Nos vemos mañana a las 10:00. ¡Gracias!", "Mensajes")
        ] { history.insert(text, source: source) }
    }

    func capture(notify: Bool = true) {
        guard !demo else { return }
        let board = NSPasteboard.general
        guard board.changeCount != changeCount else { return }
        changeCount = board.changeCount
        imageCaptureGeneration += 1
        let generation = imageCaptureGeneration
        pendingImageCapture = nil
        guard !paused else { return }
        let excluded = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        guard !excluded.contains(where: { board.types?.contains(NSPasteboard.PasteboardType($0)) == true }) else { return }
        let sourceApp = NSWorkspace.shared.frontmostApplication
        let source = sourceApp?.localizedName ?? "Portapapeles"
        let sourceBundleID = sourceApp?.bundleIdentifier
        if let fileURL = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])?.first as? URL,
           fileURL.isFileURL {
            captureFile(fileURL, source: source, sourceBundleID: sourceBundleID, changeCount: board.changeCount, generation: generation, notify: notify)
            return
        }
        let imageTypes = [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier]
        if imageTypes.contains(where: { board.types?.contains(NSPasteboard.PasteboardType($0)) == true }) {
            captureImage(from: board, source: source, sourceBundleID: sourceBundleID, changeCount: board.changeCount, generation: generation, notify: notify)
            return
        }
        guard let text = board.string(forType: .string) else { return }
        switch space {
        case .normal:
            if history.insert(text, source: source, sourceBundleID: sourceBundleID) {
                if let clip = history.latest, let linkURL = clip.linkURL { fetchLinkPreview(linkURL, clipID: clip.id, space: .normal) }
                onNormalClipInserted?(text)
                if notify { onCopy?() }
            }
        case .ghost:
            if ghostHistory.insert(text, source: source, sourceBundleID: sourceBundleID) {
                if let clip = ghostHistory.latest, let linkURL = clip.linkURL { fetchLinkPreview(linkURL, clipID: clip.id, space: .ghost) }
                if notify { onCopy?() }
            }
        case .flash, .privateSession:
            break
        }
    }

    func prepare() {
        capture(); searchExpanded = false; searchFocused = false; query = ""; highlightedID = visibleHistory.latest?.id
    }
    func move(_ offset: Int) {
        let clips = filtered
        guard !clips.isEmpty else { return }
        let index = clips.firstIndex { $0.id == highlightedID } ?? 0
        highlightedID = clips[min(max(index + offset, 0), clips.count - 1)].id
    }
    func select(_ clip: Clip) {
        switch space {
        case .normal: history.select(clip.id)
        case .ghost: ghostHistory.select(clip.id)
        case .flash: flashHistory.select(clip.id)
        case .privateSession: privateHistory.select(clip.id)
        }
    }
    func write(_ clip: Clip) {
        select(clip)
        let board = NSPasteboard.general
        board.clearContents()
        if let fileURL = clip.fileURL, let url = URL(string: fileURL), url.isFileURL {
            board.writeObjects([url as NSURL])
        } else if let imageData = clip.imageData, let imageType = clip.imageType {
            board.setData(imageData, forType: NSPasteboard.PasteboardType(imageType))
        } else {
            board.setString(clip.text, forType: .string)
        }
        changeCount = board.changeCount
        if space == .flash { flashClipboardChangeCount = changeCount }
    }

    /// Adds an authenticated Orbital transfer to Normal and makes it the
    /// system clipboard so the next paste works across devices. Updating the
    /// observed change count prevents importing it again or echoing it back.
    @discardableResult
    func insertOrbitalClip(_ text: String, source: String) -> Bool {
        guard text.utf8.count <= OrbitalClipEnvelope.maximumUTF8Bytes,
              history.insert(text, source: "Orbital · \(source)") else { return false }
        if let clip = history.latest, let linkURL = clip.linkURL { fetchLinkPreview(linkURL, clipID: clip.id, space: .normal) }
        if space == .normal { highlightedID = history.latest?.id }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        changeCount = NSPasteboard.general.changeCount
        return true
    }
    func clear() {
        switch space {
        case .normal: history.clear()
        case .ghost: ghostHistory.clear()
        case .flash: flashHistory.clear(); clearFlashTimer()
        case .privateSession:
            privateHistory.clear()
            try? vault.save(privateHistory)
        }
        highlightedID = nil
        // Do not re-import the current clipboard immediately after clearing.
        changeCount = NSPasteboard.general.changeCount
    }

    func removeHighlighted() {
        guard let id = highlightedID else { return }
        switch space {
        case .normal: history.remove(id)
        case .ghost: ghostHistory.remove(id)
        case .flash: flashHistory.remove(id); if flashHistory.clips.isEmpty { clearFlashTimer() }
        case .privateSession:
            privateHistory.remove(id)
            try? vault.save(privateHistory)
        }
        highlightedID = visibleHistory.selected?.id
    }

    func switchSpace(_ newSpace: ClipboardSpace) {
        guard newSpace != space else { return }
        if space == .privateSession { lockPrivate() }
        if space == .flash { clearFlashTimer() }
        space = newSpace
        query = ""; highlightedID = visibleHistory.latest?.id
        if newSpace == .privateSession { unlockPrivate() }
        if newSpace == .ghost, ghostSoundEnabled { Self.playSystemSound("Submarine") }
        if newSpace == .flash, flashSoundEnabled { Self.playSound(resource: "malarbrush-camera-flash-204151") }
        if newSpace == .privateSession, privateSoundEnabled { Self.playSound(resource: "eaglaxle-switching-button-3-461630") }
    }

    func unlockPrivate() {
        guard !privateUnlockInProgress, !privateUnlocked else { return }
        privateUnlockGeneration += 1
        let generation = privateUnlockGeneration
        privateUnlockInProgress = true
        privateError = nil
        vault.unlock { [weak self] result in
            guard let self else { return }
            guard generation == self.privateUnlockGeneration else { return }
            self.privateUnlockInProgress = false
            switch result {
            case .success(let value):
                guard self.space == .privateSession else {
                    self.vault.lock()
                    self.privateHistory.clear()
                    self.privateUnlocked = false
                    self.savePrivateAfterUnlock = false
                    return
                }
                self.privateHistory = value
                self.privateUnlocked = true
                self.highlightedID = value.latest?.id
                if self.savePrivateAfterUnlock {
                    self.savePrivateAfterUnlock = false
                    self.saveCurrentToPrivate()
                }
            case .failure(let error):
                self.savePrivateAfterUnlock = false
                self.privateError = error.localizedDescription
            }
        }
    }

    func saveCurrentToPrivate() {
        guard privateUnlocked else {
            savePrivateAfterUnlock = true
            privateError = "Confirma con Touch ID o la contraseña de macOS para guardar esta copia."
            unlockPrivate()
            return
        }
        guard let text = NSPasteboard.general.string(forType: .string) else { return }
        if privateHistory.insert(text, source: "Guardado manualmente") {
            do { try vault.save(privateHistory) }
            catch { privateError = error.localizedDescription }
            highlightedID = privateHistory.latest?.id
        }
    }

    func saveHighlightedToGhost() {
        guard let clip = highlighted else { return }
        if let imageData = clip.imageData, let thumbnail = clip.imageThumbnail, let imageType = clip.imageType {
            guard ghostHistory.insertImage(imageData, thumbnail: thumbnail, imageType: imageType, source: clip.source, sourceBundleID: clip.sourceBundleID) else { return }
        } else {
            guard ghostHistory.insert(clip.text, source: clip.source, sourceBundleID: clip.sourceBundleID) else { return }
        }
        if space == .normal { history.remove(clip.id) }
        enforceScreenshotMemoryBudget()
    }

    func clearScreenshots() {
        imageCaptureGeneration += 1
        pendingImageCapture = nil
        let wasHighlightedImage = highlighted?.isImage == true
        history.removeImages()
        ghostHistory.removeImages()
        if wasHighlightedImage { highlightedID = filtered.first?.id }
    }

    private func captureImage(from board: NSPasteboard, source: String, sourceBundleID: String?, changeCount: Int, generation: Int, notify: Bool) {
        guard captureScreenshots, space == .normal || space == .ghost else { return }
        let candidateTypes = [UTType.png.identifier, UTType.jpeg.identifier, UTType.heic.identifier, UTType.tiff.identifier]
        guard let imageType = candidateTypes.first(where: { board.types?.contains(NSPasteboard.PasteboardType($0)) == true }),
              let sourceData = board.data(forType: NSPasteboard.PasteboardType(imageType)),
              !sourceData.isEmpty, sourceData.count <= Self.maximumSourceImageBytes else { return }
        let capture = ImageCapture(data: sourceData, type: imageType, source: source, sourceBundleID: sourceBundleID,
                                   changeCount: changeCount, generation: generation, space: space, notify: notify)
        if imageCaptureInFlight {
            // Keep only the newest waiting image; rapid copies cannot queue up
            // many full-size payloads behind a slow decode.
            pendingImageCapture = capture
        } else {
            imageCaptureInFlight = true
            processImageCapture(capture)
        }
    }

    private func captureFile(_ url: URL, source: String, sourceBundleID: String?, changeCount: Int, generation: Int, notify: Bool) {
        guard space == .normal || space == .ghost else { return }
        let capture = FileCapture(url: url, source: source, sourceBundleID: sourceBundleID, changeCount: changeCount,
                                  generation: generation, space: space, notify: notify)
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true
        guard isImage, captureScreenshots else {
            insertFile(capture, image: nil)
            return
        }
        imageProcessingQueue.async { [weak self] in
            let accessed = url.startAccessingSecurityScopedResource()
            defer { if accessed { url.stopAccessingSecurityScopedResource() } }
            let data = (try? Data(contentsOf: url, options: [.mappedIfSafe])).flatMap { $0.count <= Self.maximumSourceImageBytes ? $0 : nil }
            let processed = data.flatMap { Self.processImage($0, type: UTType(filenameExtension: url.pathExtension)?.identifier ?? UTType.png.identifier) }
            DispatchQueue.main.async {
                guard let self else { return }
                self.insertFile(capture, image: processed)
            }
        }
    }

    private func insertFile(_ capture: FileCapture, image: ProcessedImage?) {
        guard imageCaptureGeneration == capture.generation,
              changeCount == capture.changeCount,
              NSPasteboard.general.changeCount == capture.changeCount,
              capture.space == space else { return }
        let inserted: Bool
        if capture.space == .normal {
            inserted = history.insertFile(capture.url, imageData: image?.data,
                                          thumbnail: image?.thumbnail, imageType: image?.type, source: capture.source, sourceBundleID: capture.sourceBundleID)
            if inserted { highlightedID = history.latest?.id }
        } else {
            inserted = ghostHistory.insertFile(capture.url, imageData: image?.data,
                                               thumbnail: image?.thumbnail, imageType: image?.type, source: capture.source, sourceBundleID: capture.sourceBundleID)
            if inserted { highlightedID = ghostHistory.latest?.id }
        }
        if inserted { enforceScreenshotMemoryBudget() }
        if inserted, capture.notify { onCopy?() }
    }

    private func fetchLinkPreview(_ string: String, clipID: UUID, space: ClipboardSpace) {
        guard let url = URL(string: string), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return }
        let provider = LPMetadataProvider()
        provider.timeout = 8
        pendingLinkProviders[clipID] = provider
        provider.startFetchingMetadata(for: url) { [weak self] metadata, _ in
            guard let self else { return }
            let title = metadata?.title
            guard let imageProvider = metadata?.imageProvider else {
                DispatchQueue.main.async { self.finishLinkPreview(clipID: clipID, space: space, title: title, image: nil) }
                return
            }
            imageProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                let thumbnail = data.flatMap { Self.processImage($0, type: UTType.image.identifier)?.thumbnail }
                DispatchQueue.main.async { self.finishLinkPreview(clipID: clipID, space: space, title: title, image: thumbnail) }
            }
        }
    }

    private func finishLinkPreview(clipID: UUID, space: ClipboardSpace, title: String?, image: Data?) {
        pendingLinkProviders[clipID] = nil
        if space == .normal { history.updateLinkPreview(id: clipID, title: title, image: image) }
        else if space == .ghost { ghostHistory.updateLinkPreview(id: clipID, title: title, image: image) }
        enforceScreenshotMemoryBudget()
    }

    private func persistHistory() {
        let archive = ClipboardHistoryArchive(normal: history, ghost: ghostHistory)
        historyPersistenceQueue.async { archive.save() }
    }

    private func processImageCapture(_ capture: ImageCapture) {
        imageProcessingQueue.async { [weak self] in
            let processed = Self.processImage(capture.data, type: capture.type)
            DispatchQueue.main.async {
                guard let self else { return }
                self.finishImageCapture(capture, processed: processed)
            }
        }
    }

    private func finishImageCapture(_ capture: ImageCapture, processed: ProcessedImage?) {
        imageCaptureInFlight = false
        if let processed,
           imageCaptureGeneration == capture.generation,
           changeCount == capture.changeCount,
           NSPasteboard.general.changeCount == capture.changeCount,
           captureScreenshots {
            let inserted: Bool
            if capture.space == .normal {
                inserted = history.insertImage(processed.data, thumbnail: processed.thumbnail,
                                               imageType: processed.type, source: capture.source, sourceBundleID: capture.sourceBundleID)
                if inserted, space == .normal { highlightedID = history.latest?.id }
            } else {
                inserted = ghostHistory.insertImage(processed.data, thumbnail: processed.thumbnail,
                                                    imageType: processed.type, source: capture.source, sourceBundleID: capture.sourceBundleID)
                if inserted, space == .ghost { highlightedID = ghostHistory.latest?.id }
            }
            if inserted {
                enforceScreenshotMemoryBudget()
                if capture.notify { onCopy?() }
            }
        }
        if let pending = pendingImageCapture {
            pendingImageCapture = nil
            if pending.generation == imageCaptureGeneration,
               pending.changeCount == NSPasteboard.general.changeCount, captureScreenshots {
                imageCaptureInFlight = true
                processImageCapture(pending)
            }
        }
    }

    private static func processImage(_ sourceData: Data, type: String) -> ProcessedImage? {
        guard let imageSource = CGImageSourceCreateWithData(sourceData as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              CGImageSourceGetCount(imageSource) > 0,
              let thumbnailImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 520,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false
              ] as CFDictionary),
              let thumbnailData = encodePNG(thumbnailImage) else { return nil }

        var storedData = sourceData
        var storedType = type
        if storedData.count > History.maximumImageBytes,
           let smallerImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 2400,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false
           ] as CFDictionary),
           let resizedData = encodePNG(smallerImage) {
            storedData = resizedData
            storedType = UTType.png.identifier
        }
        guard storedData.count <= History.maximumImageBytes else { return nil }
        return ProcessedImage(data: storedData, thumbnail: thumbnailData, type: storedType)
    }

    private static func encodePNG(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func enforceScreenshotMemoryBudget() {
        func imageClips(in history: History) -> [Clip] { history.clips.filter { $0.imageData != nil } }
        while history.imageByteCount + ghostHistory.imageByteCount > History.maximumTotalImageBytes ||
                imageClips(in: history).count + imageClips(in: ghostHistory).count > History.maximumImageCount {
            let normalOldest = imageClips(in: history).last
            let ghostOldest = imageClips(in: ghostHistory).last
            if let normalOldest, let ghostOldest {
                if normalOldest.date <= ghostOldest.date { history.removeOldestImage() }
                else { ghostHistory.removeOldestImage() }
            } else if normalOldest != nil { history.removeOldestImage() }
            else if ghostOldest != nil { ghostHistory.removeOldestImage() }
            else {
                let normalLinkDate = history.removeOldestLinkPreview()
                let ghostLinkDate = ghostHistory.removeOldestLinkPreview()
                if normalLinkDate != nil || ghostLinkDate != nil { continue }
                else { break }
            }
        }
        if highlightedID != nil, !filtered.contains(where: { $0.id == highlightedID }) {
            highlightedID = filtered.first?.id
        }
    }

    func lockPrivate() {
        privateUnlockGeneration += 1
        privateUnlockInProgress = false
        vault.lock(); privateHistory.clear(); privateUnlocked = false
        if space == .privateSession {
            highlightedID = nil
            privateError = "Privado está bloqueado. Pulsa el icono de la izquierda para desbloquearlo."
        }
    }

    func beginFlash(text: String) {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if space == .flash { clearFlashTimer() }
        switchSpace(.flash)
        flashHistory.clear()
        flashHistory.insert(text, source: "Flash")
        flashText = text
        flashClipboardChangeCount = NSPasteboard.general.changeCount
        flashExpiresAt = Date().addingTimeInterval(60)
        highlightedID = flashHistory.latest?.id
        flashTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.eraseFlashClipboardIfUnchanged()
            self.flashHistory.clear(); self.flashExpiresAt = nil; self.highlightedID = nil
            self.changeCount = NSPasteboard.general.changeCount
            if self.space == .flash { self.space = .normal }
            self.flashTimer = nil
        }
        onCopy?()
    }

    private func clearFlashTimer() {
        flashTimer?.invalidate(); flashTimer = nil; flashExpiresAt = nil
        eraseFlashClipboardIfUnchanged()
        flashHistory.clear(); highlightedID = nil
        if space == .flash { space = .normal }
    }

    private func eraseFlashClipboardIfUnchanged() {
        guard let flashText, NSPasteboard.general.string(forType: .string) == flashText,
              NSPasteboard.general.changeCount == flashClipboardChangeCount else {
            self.flashText = nil; flashClipboardChangeCount = nil; return
        }
        NSPasteboard.general.clearContents()
        changeCount = NSPasteboard.general.changeCount
        self.flashText = nil
        flashClipboardChangeCount = nil
    }

    func clearAll(_ target: ClipboardSpace) {
        switch target {
        case .normal: history.clear()
        case .ghost: ghostHistory.clear()
        case .flash: clearFlashTimer(); flashHistory.clear()
        case .privateSession:
            lockPrivate()
            do { try vault.erase() } catch { privateError = error.localizedDescription }
        }
        if space == target { highlightedID = nil }
    }

    func prepareToQuit() {
        clearFlashTimer()
        flashHistory.clear()
        lockPrivate()
    }

    private static var activeSounds: [UUID: NSSound] = [:]

    private static func playSystemSound(_ name: String) {
        guard let sound = NSSound(named: NSSound.Name(name)) else { return }
        sound.volume = 0.35
        sound.play()
    }

    private static func playSound(resource name: String) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "mp3"),
              let sound = NSSound(contentsOf: url, byReference: false) else { return }
        sound.volume = 0.35
        let id = UUID()
        activeSounds[id] = sound
        sound.play()
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { activeSounds[id] = nil }
    }

    deinit { flashTimer?.invalidate(); vault.lock() }
}
