import SwiftUI
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins
#if canImport(ClipboardCore)
import ClipboardCore
#endif

private let ink = Color.primary
private let accent = Color(red: 0.52, green: 0.20, blue: 0.92)

struct PickerView: View {
    static let bubbleWidth: CGFloat = 360
    static let bubbleHeight: CGFloat = 44
    static let cardsHeight: CGFloat = 176
    // Each step exposes the next card as the stack recedes toward the right.
    static let screenshotCardWidth: CGFloat = 244
    static let screenshotCardHeight: CGFloat = 138
    static let screenshotCardOffsets: [CGFloat] = [0, 92, 152]
    static let searchHeight: CGFloat = 40
    static let itemSpacing: CGFloat = 8
    static let animationPadding: CGFloat = 24
    static let width = bubbleWidth + animationPadding * 2
    static let height = cardsHeight + bubbleHeight + searchHeight + itemSpacing * 2 + animationPadding * 2
    static let bubbleOffsetFromPanelBottom = animationPadding + searchHeight + itemSpacing
    @ObservedObject var store: ClipboardStore
    @ObservedObject var orbital: OrbitalCoordinator
    @ObservedObject var motion: PickerMotion
    let sendToAndroid: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Namespace private var cardsNamespace
    let paste: (Clip) -> Void
    let switchSpace: () -> Void
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        let clips = store.filtered
        let selected = clips.firstIndex { $0.id == store.highlightedID } ?? 0
        return ZStack(alignment: .topLeading) {
            VStack(spacing: Self.itemSpacing) {
                screenshotStack
                    .frame(width: Self.bubbleWidth, height: Self.cardsHeight, alignment: .bottomLeading)
                capsule(clips: clips, selected: selected)
                if store.searchExpanded {
                    HStack {
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Buscar", text: $store.query)
                                .textFieldStyle(.plain)
                                .focused($searchFieldFocused)
                                .onSubmit { if let clip = store.highlighted { paste(clip) } }
                            if !store.query.isEmpty {
                                Button { store.query = ""; searchFieldFocused = true } label: {
                                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 12)
                        .frame(width: 260, height: Self.searchHeight)
                        .background(.ultraThinMaterial, in: Capsule())
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.75))
                    }
                    .frame(width: Self.bubbleWidth, height: Self.searchHeight)
                    .transition(.move(edge: .top).combined(with: .opacity))
                } else {
                    Color.clear.frame(width: Self.bubbleWidth, height: Self.searchHeight)
                }
            }
            .padding(Self.animationPadding)
        }
        .frame(width: Self.width, height: Self.height, alignment: .topLeading)
        .scaleEffect(motion.scale)
        .opacity(motion.opacity)
        // Animate layer transforms so the system compositor can move cached
        // thumbnails smoothly without decoding full-size images per frame.
        .animation(.interpolatingSpring(stiffness: 270, damping: 25), value: store.highlightedID)
        .animation(.easeOut(duration: 0.18), value: store.searchExpanded)
        .onChange(of: searchFieldFocused) { store.searchFocused = $0 }
        .onChange(of: store.searchExpanded) { searchFieldFocused = $0 }
        .accessibilityLabel(store.highlighted.map { "\(Distribution.isAppStore ? "Copiar" : "Pegar"): \($0.compactPreview)" } ?? "Historial vacío")
    }

    @ViewBuilder
    private var screenshotStack: some View {
        let cards = screenshotCards
        if !cards.isEmpty {
            ZStack(alignment: .topLeading) {
                ForEach(cards, id: \.id) { clip in
                    let index = cards.firstIndex(where: { $0.id == clip.id }) ?? 0
                    HistoryCard(clip: clip)
                        .frame(width: Self.screenshotCardWidth, height: Self.screenshotCardHeight)
                        // Receding cards converge toward a vanishing point to
                        // the right, getting smaller and fading as they go.
                        .offset(x: Self.screenshotCardOffsets[min(index, Self.screenshotCardOffsets.count - 1)],
                                y: 0)
                        .scaleEffect(pow(0.84, CGFloat(index)), anchor: .center)
                        .rotation3DEffect(.degrees(-Double(index) * 13), axis: (x: 0, y: 1, z: 0),
                                          anchor: .center, perspective: 0.8)
                        .opacity(pow(0.72, Double(index)))
                        .zIndex(Double(cards.count - index))
                        .matchedGeometryEffect(id: clip.id, in: cardsNamespace)
                        .onTapGesture { store.highlightedID = clip.id }
                        .transition(.asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity).combined(with: .scale(scale: 0.96)),
                            removal: .move(edge: .leading).combined(with: .opacity).combined(with: .scale(scale: 0.98))))
                        .accessibilityLabel("Captura de \(clip.source), \(clip.date.formatted(date: .abbreviated, time: .shortened))")
                }
            }
            .frame(width: Self.bubbleWidth, height: Self.cardsHeight, alignment: .bottomLeading)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else {
            Color.clear
        }
    }

    private func capsule(clips: [Clip], selected: Int) -> some View {
        HStack(spacing: 8) {
            Button(action: switchSpace) {
                Group {
                    if store.space == .ghost {
                        Image(systemName: "square.stack.3d.up")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                    } else {
                        Image(systemName: store.space.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(store.space == .flash ? Color.yellow : .primary.opacity(0.8))
                    }
                }
                .frame(width: 28, height: 28)
                .background(.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Cambiar espacio")
            VStack(alignment: .leading, spacing: 0) {
                if selected > 0 {
                    Text(clips[selected - 1].compactPreview)
                        .font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary.opacity(0.38))
                        .frame(height: 13, alignment: .bottom).transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                Text(store.space == .privateSession && !store.privateUnlocked
                     ? (store.privateError ?? "Desbloqueando Privado…")
                     : (store.highlighted?.compactPreview ?? emptyMessage))
                    .font(.system(size: 12, weight: .medium)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(.primary)
                    .frame(height: 18)
                    .id(store.highlightedID)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                if selected + 1 < clips.count {
                    Text(clips[selected + 1].compactPreview)
                        .font(.system(size: 10)).lineLimit(1).foregroundStyle(.secondary.opacity(0.38))
                        .frame(height: 13, alignment: .top).transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(maxWidth: .infinity)
            .help(Distribution.isAppStore ? "Pulsa Enter para copiar; después pulsa ⌘V en la app de destino." : "Pulsa Enter para pegar la copia seleccionada.")
            if store.space == .flash, store.showFlashTimer, let expiry = store.flashExpiresAt {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    Text("\(max(0, Int(expiry.timeIntervalSince(context.date).rounded(.up))))s")
                        .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.yellow)
                        .frame(minWidth: 24)
                }
            }
            if let clip = store.highlighted,
               let index = store.filtered.firstIndex(where: { $0.id == clip.id }) {
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 16)
                Text("\(index + 1)/\(store.filtered.count)")
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 27, height: 27)
                    .background(accent.opacity(0.10), in: Circle())
                    .help(Distribution.isAppStore ? "Pulsa Enter para copiar" : "Pulsa Enter para pegar")
                    .accessibilityLabel(Distribution.isAppStore ? "Pulsa Enter para copiar" : "Pulsa Enter para pegar")
            }
            if store.space == .privateSession {
                Button(action: store.saveCurrentToPrivate) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary).frame(width: 18, height: 26)
                }
                .buttonStyle(.plain).help("Guardar el portapapeles en Privado")
            }
            Button(action: sendToAndroid) {
                OrbitalMark(size: 17, isActive: canSendHighlightedToAndroid)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help(orbital.pairedDevices.count == 1
                  ? "Enviar la copia seleccionada a \(orbital.pairedDevices[0].name)"
                  : "Enviar la copia seleccionada a Android por Orbital")
            .accessibilityLabel("Enviar a Android por Orbital")
            Button {
                if store.searchExpanded {
                    store.searchExpanded = false
                    store.searchFocused = false
                    searchFieldFocused = false
                    store.query = ""
                } else {
                    store.searchExpanded = true
                    searchFieldFocused = true
                }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(store.searchExpanded ? accent : .secondary)
                    .frame(width: 28, height: 28)
                    .background(.primary.opacity(0.045), in: Circle())
            }
            .buttonStyle(.plain)
            .help("Buscar en el historial")
            .accessibilityLabel("Buscar en el historial")
        }
        .padding(.horizontal, 8)
        .frame(width: Self.bubbleWidth, height: Self.bubbleHeight)
        .contentShape(Capsule())
        .background {
            Capsule().fill(.ultraThinMaterial)
                .overlay {
                    Capsule().fill(LinearGradient(
                        colors: colorScheme == .dark
                            ? [Color(white: 0.19).opacity(0.94), Color(white: 0.13).opacity(0.94)]
                            : [.white.opacity(0.98), Color(white: 0.97).opacity(0.94)],
                        startPoint: .top, endPoint: .bottom))
                }
        }
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(.primary.opacity(0.10), lineWidth: 0.75))
        .overlay(Capsule().inset(by: 1).strokeBorder(.white.opacity(colorScheme == .dark ? 0.08 : 0.95), lineWidth: 0.75))
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.10), radius: 7, x: 0, y: 3)
    }

    private var screenshotCards: [Clip] {
        let clips = store.filtered
        guard !clips.isEmpty else { return [] }
        let selectedIndex = clips.firstIndex { $0.id == store.highlightedID } ?? 0
        var cards = [clips[selectedIndex]]
        cards.append(contentsOf: clips.dropFirst(selectedIndex + 1).prefix(2))
        if cards.count < 3, selectedIndex > 0 {
            cards.append(contentsOf: clips[..<selectedIndex].suffix(3 - cards.count))
        }
        return cards
    }

    private var canSendHighlightedToAndroid: Bool {
        guard let clip = store.highlighted, !clip.isImage else { return false }
        return orbital.mayManuallyShare(space: store.space, text: clip.text)
    }

    private var emptyMessage: String {
        switch store.space {
        case .normal: "Copia algo con ⌘C"
        case .ghost: "Guarda aquí una copia Fantasma"
        case .flash: "Flash · ⌥⇧C para copiar"
        case .privateSession: "Aún no hay copias privadas"
        }
    }
}

private struct HistoryCard: View {
    private static let cardWidth: CGFloat = 240
    private static let previewHeight: CGFloat = 109
    private static let previewCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 3
        cache.totalCostLimit = 4 * 1_024 * 1_024
        return cache
    }()
    private static let appIconCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 48
        return cache
    }()
    let clip: Clip
    @State private var preview: NSImage?
    private let sourceAppIcon: NSImage?

    init(clip: Clip) {
        self.clip = clip
        if let bundleID = clip.sourceBundleID {
            let key = bundleID as NSString
            if let cached = Self.appIconCache.object(forKey: key) {
                sourceAppIcon = cached
            } else if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: appURL.path)
                Self.appIconCache.setObject(icon, forKey: key)
                sourceAppIcon = icon
            } else {
                sourceAppIcon = nil
            }
        } else {
            sourceAppIcon = nil
        }
        let key = clip.id.uuidString as NSString
        if let cached = Self.previewCache.object(forKey: key) {
            _preview = State(initialValue: cached)
        } else if let data = clip.linkImage ?? clip.imageThumbnail, let image = NSImage(data: data) {
            Self.previewCache.setObject(image, forKey: key, cost: data.count)
            _preview = State(initialValue: image)
        } else {
            _preview = State(initialValue: nil)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                if let sourceAppIcon {
                    Image(nsImage: sourceAppIcon).resizable().frame(width: 14, height: 14).clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).foregroundStyle(accent)
                }
                Text(kind).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 4)
                Text(clip.date, style: .time)
                    .font(.system(size: 9, design: .rounded)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).frame(height: 29)
            if let image = preview {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: Self.cardWidth, height: clip.isLink ? 82 : Self.previewHeight)
                    .clipped()
                if clip.isLink {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(clip.linkTitle ?? linkHost).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        Text(linkHost).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .padding(.horizontal, 9).frame(maxWidth: .infinity, minHeight: 27, alignment: .leading)
                    .background(.regularMaterial)
                }
            } else if clip.isLink {
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.linkTitle ?? linkHost).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                    Text(linkHost).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else if clip.isFile {
                Label(clip.fileName ?? "Archivo", systemImage: clip.isImageFile ? "photo" : "doc")
                    .font(.system(size: 12, weight: .medium)).lineLimit(2).padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            } else {
                Text(clip.compactPreview).font(.system(size: 11, weight: .medium)).lineLimit(5)
                    .padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 15, style: .continuous).strokeBorder(.white.opacity(0.85), lineWidth: 1))
        .shadow(color: .black.opacity(0.16), radius: 12, x: 0, y: 6)
        .onChange(of: clip.linkImage) { data in
            guard let data, let image = NSImage(data: data) else { return }
            preview = image
            Self.previewCache.setObject(image, forKey: clip.id.uuidString as NSString, cost: data.count)
        }
    }

    private var kind: String {
        if clip.isImageFile { return "Imagen" }
        if clip.isFile { return "Archivo" }
        if clip.isImage { return "Imagen" }
        if clip.isLink { return "Link" }
        return "Texto"
    }

    private var symbol: String {
        if clip.isImageFile { return "photo" }
        if clip.isFile { return "doc" }
        if clip.isImage { return "photo" }
        if clip.isLink { return "link" }
        return "text.alignleft"
    }

    private var linkHost: String { URL(string: clip.linkURL ?? "")?.host ?? clip.linkURL ?? "Enlace" }
}

private struct GhostMark: View {
    let color: Color
    let size: CGFloat

    var body: some View {
        GhostBody()
            .fill(color, style: FillStyle(eoFill: true))
            .aspectRatio(0.83, contentMode: .fit)
            .frame(width: size * 0.83, height: size)
            .accessibilityLabel("Fantasma")
    }
}

private struct GhostBody: Shape {
    func path(in rect: CGRect) -> Path {
        let scale = min(rect.width / 100, rect.height / 120)
        let ox = rect.midX - 50 * scale
        let oy = rect.midY - 60 * scale
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: ox + x * scale, y: oy + y * scale) }
        var path = Path()
        path.move(to: point(50, 3))
        path.addCurve(to: point(76, 31), control1: point(50, 3), control2: point(75, 7))
        path.addCurve(to: point(80, 42), control1: point(77, 35), control2: point(78, 41))
        path.addCurve(to: point(96, 34), control1: point(87, 43), control2: point(95, 27))
        path.addCurve(to: point(91, 53), control1: point(100, 42), control2: point(98, 47))
        path.addCurve(to: point(76, 63), control1: point(86, 58), control2: point(81, 60))
        path.addCurve(to: point(87, 88), control1: point(81, 73), control2: point(89, 80))
        path.addCurve(to: point(83, 104), control1: point(90, 97), control2: point(88, 104))
        path.addCurve(to: point(67, 103), control1: point(78, 108), control2: point(73, 101))
        path.addCurve(to: point(50, 117), control1: point(60, 113), control2: point(59, 117))
        path.addCurve(to: point(33, 103), control1: point(41, 117), control2: point(40, 113))
        path.addCurve(to: point(17, 104), control1: point(27, 101), control2: point(22, 108))
        path.addCurve(to: point(13, 88), control1: point(12, 104), control2: point(10, 97))
        path.addCurve(to: point(24, 63), control1: point(11, 80), control2: point(19, 73))
        path.addCurve(to: point(9, 53), control1: point(19, 60), control2: point(14, 58))
        path.addCurve(to: point(4, 34), control1: point(2, 47), control2: point(0, 42))
        path.addCurve(to: point(20, 42), control1: point(5, 27), control2: point(13, 43))
        path.addCurve(to: point(24, 31), control1: point(22, 41), control2: point(23, 35))
        path.addCurve(to: point(50, 3), control1: point(25, 7), control2: point(50, 3))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: ox + 32 * scale, y: oy + 34 * scale, width: 11 * scale, height: 15 * scale))
        path.addEllipse(in: CGRect(x: ox + 57 * scale, y: oy + 34 * scale, width: 11 * scale, height: 15 * scale))
        path.move(to: point(41, 59))
        path.addQuadCurve(to: point(59, 59), control: point(50, 74))
        path.addQuadCurve(to: point(41, 59), control: point(50, 62))
        path.closeSubpath()
        return path
    }
}

struct SettingsView: View {
    @ObservedObject var store: ClipboardStore
    @ObservedObject var orbital: OrbitalCoordinator
    @ObservedObject var permission: AccessibilityPermission
    @ObservedObject var loginItem: LoginItemSettings
    let shortcutFailures: [String]
    let appIcon: NSImage
    let windowHeight: CGFloat
    let onSwitchSpace: (ClipboardSpace) -> Void
    @State private var showPreferences = false

    var body: some View {
        HStack(spacing: 0) {
            settingsSidebar
            Group {
                if showPreferences {
                    ScrollView { preferencesPane }
                } else {
                    historyPane
                }
            }
            .padding(.horizontal, 26)
            .padding(.vertical, 24)
            .frame(width: 795, height: windowHeight, alignment: .topLeading)
        }
        .frame(width: 1040, height: windowHeight, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var historyPane: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(store.space.rawValue).font(.system(size: 22, weight: .bold))
                Text(spaceSubtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            historyPanel
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var preferencesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Ajustes").font(.system(size: 30, weight: .bold)).tracking(-0.5)
                Text("Atajos, privacidad y funcionamiento.").font(.system(size: 14)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Atajos", subtitle: Distribution.isAppStore
                               ? "Abre el historial y copia una selección al portapapeles."
                               : "Abre y pega sin interrumpir lo que estás haciendo.")
                VStack(spacing: 12) {
                    shortcut(Distribution.isAppStore ? "Copiar última copia" : "Pegar la última copia", "⌥ V",
                             Distribution.isAppStore ? "Copia la selección más reciente. Luego pulsa ⌘V en la app de destino."
                                 : "Pega lo último que copiaste con ⌘C.")
                    Divider()
                    shortcut(Distribution.isAppStore ? "Copiar desde el historial" : "Elegir del historial", "⌥ ⇧ V",
                             Distribution.isAppStore ? "Recorre con ↑ y ↓; pulsa Return para copiar. Después, ⌘V en la app de destino."
                                 : "Desplázate por las copias y selecciónalas.")
                    Divider()
                    shortcut("Captura Flash", "⌥ ⇧ C", Distribution.isAppStore
                             ? "Primero copia el texto con ⌘C. Flash lo conserva por 60 segundos."
                             : "Guarda la selección activa por 60 segundos.")
                }.padding(16).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                if !Distribution.isAppStore {
                    Text("Elige con el scroll o haz clic en una card para seleccionarla; pulsa Enter para pegar. Hacer clic fuera cierra el widget.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
            .shadow(color: Color(red: 0.31, green: 0.22, blue: 0.43).opacity(0.035), radius: 14, x: 0, y: 5)

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Privacidad y captura")
                VStack(alignment: .leading, spacing: 7) {
                    settingsToggle("Conservar historial local entre aperturas", isOn: $store.keepClipboardHistory)
                    settingsToggle("Pausar captura del portapapeles", isOn: $store.paused)
                    settingsToggle("Sonido al activar Privado", isOn: $store.privateSoundEnabled)
                    settingsToggle("Sonido spooky al activar Fantasma", isOn: $store.ghostSoundEnabled)
                    settingsToggle("Sonido al activar Flash", isOn: $store.flashSoundEnabled)
                    settingsToggle("Mostrar contador de Flash", isOn: $store.showFlashTimer)
                    settingsToggle("Capturar imágenes del portapapeles", isOn: $store.captureScreenshots)
                    settingsToggle("Mostrar screenshots en el widget", isOn: $store.showScreenshots)
                    Button(role: .destructive) { store.clearScreenshots() } label: {
                        Label("Borrar screenshots guardadas (\(store.screenshotCount))", systemImage: "trash")
                    }
                    .controlSize(.small)
                    .disabled(store.screenshotCount == 0)
                    settingsToggle(Distribution.isAppStore ? "Mostrar indicador al copiar" : "Mostrar LED al copiar y pegar", isOn: $store.showActivity)
                }
                Text("El historial Normal y Fantasma se guarda solo en este Mac, con acceso restringido a tu usuario; no se sincroniza con iCloud. Puedes desactivar la conservación para borrar el archivo local. Imágenes y miniaturas se procesan en segundo plano y tienen un límite conjunto de 12 elementos y 24 MB; los originales mayores de 32 MB se omiten y los demás se reducen si hace falta.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Privado se bloquea al cambiar de espacio y vuelve a pedir autenticación cuando ingresas. Flash elimina su copia al minuto si aún está en el portapapeles. Las vistas previas de links se obtienen desde el sitio al copiar la URL.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.space == .privateSession, let error = store.privateError, !store.privateUnlocked {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
            .shadow(color: Color(red: 0.31, green: 0.22, blue: 0.43).opacity(0.035), radius: 14, x: 0, y: 5)

            orbitalPanel

            if Distribution.isAppStore {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("Cómo pegar")
                    Text("Paste Shifter copia el texto seleccionado al portapapeles. Vuelve a la app donde quieres pegarlo y pulsa ⌘V.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    settingsToggle("Abrir al iniciar sesión", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                    if loginItem.needsApproval {
                        Button("Abrir Ítems de inicio…") { loginItem.openSettings() }
                    }
                    if let error = loginItem.errorMessage {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(15)
                .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
                .shadow(color: Color(red: 0.31, green: 0.22, blue: 0.43).opacity(0.035), radius: 14, x: 0, y: 5)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeading("macOS y Paste Shifter")
                    VStack(alignment: .leading, spacing: 10) {
                        Label(permission.granted ? "Accesibilidad activada" : "Falta permiso de Accesibilidad", systemImage: permission.granted ? "checkmark.circle.fill" : "hand.raised.fill")
                            .font(.system(size: 12, weight: .semibold)).foregroundStyle(permission.granted ? Color.green : ink)
                        Text("Permite pegar y usar el scroll desde cualquier parte de la pantalla. El historial funciona sin este permiso.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        if !permission.granted {
                            HStack {
                                Button("Solicitar acceso") { permission.request() }
                                Button("Abrir Accesibilidad…") { permission.openSettings() }
                            }.controlSize(.small)
                            HStack {
                                Button("Mostrar en Finder") { permission.revealApplication() }
                                Button("Volver a comprobar") { permission.refresh() }
                            }.font(.system(size: 11))
                        }
                        if store.globalScrollUnavailable {
                            Label("El scroll global no está disponible. Revisa Accesibilidad y vuelve a abrir el historial.", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        if !shortcutFailures.isEmpty {
                            Label("Atajo en uso por otra app: \(shortcutFailures.joined(separator: ", ")).", systemImage: "exclamationmark.triangle")
                                .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                        Divider()
                        settingsToggle("Abrir al iniciar sesión", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                        if loginItem.needsApproval {
                            Button("Abrir Ítems de inicio…") { loginItem.openSettings() }
                        }
                        if let error = loginItem.errorMessage {
                            Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                        }
                    }.padding(15).background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Borrar datos", subtitle: "Elimina el contenido guardado en cada espacio.")
                HStack(spacing: 8) {
                    clearButton("Normal", space: .normal)
                    clearButton("Fantasma", space: .ghost)
                    clearButton("Flash", space: .flash)
                    clearButton("Privado", space: .privateSession)
                }
                HStack {
                    Text("Normal y Fantasma se guardan localmente entre aperturas si la conservación está activada.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    Button("Vaciar Normal", role: .destructive) { store.clear() }.controlSize(.small)
                }
            }
            .padding(15)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
            .shadow(color: Color(red: 0.31, green: 0.22, blue: 0.43).opacity(0.035), radius: 14, x: 0, y: 5)
            Text("Al cerrar Ajustes, Paste Shifter sigue disponible en la barra de menú.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var orbitalPanel: some View {
        VStack(alignment: .leading, spacing: 11) {
            sectionHeading("Orbital", subtitle: "La conexión local de Paste Shifter entre tus dispositivos.")
            HStack(alignment: .top, spacing: 10) {
                OrbitalMark(size: 30)
                    .frame(width: 38, height: 38)
                    .background(accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 11))
                VStack(alignment: .leading, spacing: 4) {
                    Text("Función central · conexión local directa").font(.system(size: 12, weight: .semibold))
                    Text(orbital.connectionStatus)
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))

            Label("Orbital no será un modo aparte: los clips recibidos aparecerán en Normal, listos para pegar. Fantasma, Flash y Privado quedan fuera.", systemImage: "doc.on.clipboard")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("Pausar Orbital", isOn: $orbital.isPaused)
                .toggleStyle(.switch).controlSize(.small)
                .font(.system(size: 11, weight: .medium))

            Toggle("Sonido en el Mac al recibir una copia", isOn: $orbital.receiveSoundEnabled)
                .toggleStyle(.switch).controlSize(.small)
                .font(.system(size: 11, weight: .medium))

            Toggle("Avisarme cuando un dispositivo se reconecte", isOn: $orbital.reconnectNotificationsEnabled)
                .toggleStyle(.switch).controlSize(.small)
                .font(.system(size: 11, weight: .medium))

            if let qrData = orbital.pairingQRData, let qrImage = pairingQRImage(from: qrData),
               let expiry = orbital.pairingExpiresAt {
                HStack(alignment: .top, spacing: 14) {
                    Image(nsImage: qrImage).interpolation(.none).resizable().scaledToFit()
                        .frame(width: 190, height: 190).padding(8)
                        .background(.white, in: RoundedRectangle(cornerRadius: 10))
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Escanea con Paste Shifter para Android")
                            .font(.system(size: 12, weight: .semibold))
                        Text("El QR es de un solo uso y vence en")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(expiry, style: .timer)
                            .font(.system(size: 12, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Después compara el código de seis dígitos en ambos dispositivos.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Cancelar emparejamiento") { orbital.endPairing() }
                            .controlSize(.small)
                    }
                    .padding(.top, 6)
                    Spacer(minLength: 0)
                }
                .padding(11)
                .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 12))
            } else if orbital.isPreparingPairing {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Preparando la conexión segura…")
                        .font(.system(size: 11, weight: .medium))
                    Spacer()
                    Button("Cancelar") { orbital.endPairing() }
                        .controlSize(.small)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(accent.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
            } else if let request = orbital.pendingApproval {
                VStack(alignment: .leading, spacing: 9) {
                    Text("¿Autorizar \(request.deviceName)?")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Confirma que el siguiente código coincide con el mostrado en tu Android:")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Text(request.comparisonCode)
                        .font(.system(size: 24, weight: .bold, design: .monospaced))
                        .tracking(4)
                        .accessibilityLabel("Código de comprobación \(request.comparisonCode)")
                    HStack {
                        Button("Rechazar") { orbital.rejectPairing() }.controlSize(.small)
                        Button("Autorizar dispositivo") { orbital.approvePairing() }
                            .controlSize(.small).keyboardShortcut(.defaultAction)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            } else {
                Button {
                    orbital.beginPairing()
                } label: {
                    Label("Añadir dispositivo Android", systemImage: "qrcode")
                        .font(.system(size: 11, weight: .semibold))
                }
                .controlSize(.small)
            }

            VStack(alignment: .leading, spacing: 4) {
                Toggle("Compartir automáticamente copias nuevas de Normal", isOn: $orbital.automaticSharingEnabled)
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                    .disabled(orbital.availability != .ready)
                Text("Desactivado por defecto. También podrás compartir un clip de forma explícita.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !orbital.pairedDevices.isEmpty {
                Divider()
                Text("DISPOSITIVOS EMPAREJADOS").font(.system(size: 9, weight: .bold)).tracking(1.0).foregroundStyle(.tertiary)
                ForEach(orbital.pairedDevices) { device in
                    HStack {
                        Label(device.name, systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button("Revocar") { orbital.revokeDevice(device.id) }
                            .font(.system(size: 10)).controlSize(.small)
                    }
                }
            }
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
        .shadow(color: Color(red: 0.31, green: 0.22, blue: 0.43).opacity(0.035), radius: 14, x: 0, y: 5)
    }

    private func pairingQRImage(from payload: Data) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = payload
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)),
              let cgImage = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: cgImage, size: NSSize(width: 200, height: 200))
    }

    private var settingsSidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 34, height: 34)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Paste Shifter").font(.system(size: 12, weight: .semibold))
                    Text("AJUSTES").font(.system(size: 9, weight: .bold)).tracking(1.1).foregroundStyle(.secondary)
                }
            }
            .padding(.bottom, 28)

            Text("TUS ESPACIOS")
                .font(.system(size: 9, weight: .bold)).tracking(1.15)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 9).padding(.bottom, 9)

            sidebarSpace(.normal, symbol: "⌘", tint: .blue, subtitle: "Historial cotidiano")
            sidebarSpace(.ghost, symbol: "✳", tint: accent, subtitle: "Copias separadas")
            sidebarSpace(.flash, symbol: "bolt.fill", tint: .orange, subtitle: "Se borra en 60 s")
            sidebarSpace(.privateSession, symbol: "lock.fill", tint: .pink, subtitle: "Cifrado local")

            Spacer(minLength: 18)
            Text("PREFERENCIAS")
                .font(.system(size: 9, weight: .bold)).tracking(1.15)
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 9).padding(.bottom, 9)
            Button {
                showPreferences = true
            } label: {
                HStack(spacing: 9) {
                    Label("Ajustes", systemImage: "slider.horizontal.3")
                        .font(.system(size: 11, weight: .medium))
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right").font(.system(size: 9, weight: .semibold)).foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 9).padding(.vertical, 10)
                .frame(maxWidth: .infinity, minHeight: 42, alignment: .leading)
                .contentShape(Rectangle())
                .background(showPreferences ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
            }
            .buttonStyle(.plain)

            Spacer(minLength: 18)
            HStack(spacing: 6) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Guardado localmente").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9)
        }
        .padding(18)
        .frame(width: 245, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .topLeading)
        .background(Color(nsColor: .underPageBackgroundColor))
        .overlay(alignment: .trailing) { Rectangle().fill(Color.primary.opacity(0.09)).frame(width: 1) }
    }

    private func sidebarSpace(_ space: ClipboardSpace, symbol: String, tint: Color, subtitle: String) -> some View {
        Button {
            showPreferences = false
            onSwitchSpace(space)
        } label: {
        HStack(spacing: 9) {
            Group {
                if space == .ghost {
                    GhostMark(color: tint, size: 15)
                } else if space == .normal {
                    Text(symbol).font(.system(size: 13, weight: .semibold)).foregroundStyle(tint)
                } else {
                    Image(systemName: symbol).font(.system(size: 12, weight: .semibold)).foregroundStyle(tint)
                }
            }
            .frame(width: 28, height: 28)
            .background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(space.rawValue).font(.system(size: 11, weight: .semibold))
                Text(subtitle).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8).padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(space == store.space ? accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
        .padding(.bottom, 3)
        }
        .buttonStyle(.plain)
        .help("Ver historial de \(space.rawValue)")
    }

    private var historyPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 8) {
                    if store.space == .ghost {
                        GhostMark(color: accent, size: 15)
                    } else {
                        Image(systemName: store.space.icon).foregroundStyle(store.space == .privateSession ? .pink : accent)
                    }
                    Text("Historial")
                }
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(store.visibleHistory.clips.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.primary.opacity(0.06), in: Capsule())
            }

            if store.space == .privateSession && !store.privateUnlocked {
                VStack(spacing: 10) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 25)).foregroundStyle(.pink)
                    Text(store.privateError ?? "Confirma con Touch ID para ver tus copias privadas.")
                        .font(.system(size: 12, weight: .medium)).multilineTextAlignment(.center)
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if store.privateError != nil {
                        Button("Intentar de nuevo") { store.unlockPrivate() }.controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 185)
            } else if store.visibleHistory.clips.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "doc.on.clipboard").font(.system(size: 23)).foregroundStyle(.secondary)
                    Text("Todavía no hay copias").font(.system(size: 12, weight: .medium))
                    Text(emptyHistoryHint).font(.system(size: 10)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, minHeight: 185)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(store.visibleHistory.clips) { clip in
                            historyRow(clip)
                        }
                    }
                    .padding(.vertical, 1)
                }
                .frame(maxHeight: 235)

                if let clip = store.highlighted {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(clip.text).font(.system(size: 11)).lineLimit(4).textSelection(.enabled)
                        HStack {
                            Label(clip.source, systemImage: "app")
                            Spacer()
                            Text(clip.date.formatted(date: .abbreviated, time: .shortened))
                        }
                        .font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(11)
                    .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 11))
                }

                HStack {
                    if let clip = store.highlighted {
                        Button {
                            store.write(clip)
                        } label: {
                            Label("Copiar selección", systemImage: "doc.on.doc")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(accent)
                        .controlSize(.small).frame(width: 132, height: 25)
                        let canSendToAndroid = !clip.source.hasPrefix("Orbital ·") &&
                            orbital.mayManuallyShare(space: store.space, text: clip.text)
                        if orbital.pairedDevices.count > 1 {
                            Menu {
                                ForEach(orbital.pairedDevices) { device in
                                    Button(device.name) {
                                        orbital.sendManually(clip.text, from: store.space, to: device.id)
                                    }
                                }
                            } label: {
                                HStack(spacing: 6) {
                                    OrbitalMark(size: 17, isActive: canSendToAndroid)
                                    Text("Enviar a Android")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .help(canSendToAndroid ? "Elegir un Android conectado" : orbital.connectionStatus)
                            .buttonStyle(.bordered).controlSize(.small).frame(width: 132, height: 25)
                            .disabled(!canSendToAndroid)
                        } else {
                            Button {
                                guard canSendToAndroid,
                                      let device = orbital.pairedDevices.first else { return }
                                orbital.sendManually(clip.text, from: store.space, to: device.id)
                            } label: {
                                HStack(spacing: 6) {
                                    OrbitalMark(size: 17, isActive: canSendToAndroid)
                                    Text("Enviar a Android")
                                }
                                .frame(maxWidth: .infinity)
                            }
                            .help(canSendToAndroid
                                  ? "Enviar esta copia a \(orbital.pairedDevices.first?.name ?? "Android")"
                                  : orbital.connectionStatus)
                            .buttonStyle(.bordered).controlSize(.small).frame(width: 132, height: 25)
                            .disabled(!canSendToAndroid)
                        }
                    }
                    Spacer()
                    Button(role: .destructive) { store.removeHighlighted() } label: {
                        Label("Eliminar", systemImage: "trash")
                    }
                    .disabled(store.highlighted == nil || (store.space == .privateSession && !store.privateUnlocked))
                }
            }
        }
        .padding(15)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.primary.opacity(0.075), lineWidth: 1))
        .shadow(color: Color(red: 0.31, green: 0.22, blue: 0.43).opacity(0.035), radius: 14, x: 0, y: 5)
    }

    private func historyRow(_ clip: Clip) -> some View {
        let selected = store.highlightedID == clip.id
        return Button {
            store.highlightedID = clip.id
            store.select(clip)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "text.alignleft")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(accent)
                    .frame(width: 27, height: 27)
                    .background(accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                VStack(alignment: .leading, spacing: 3) {
                    Text(clip.preview).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    Text(clip.source).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                Text(clip.date, style: .time).font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            .contentShape(RoundedRectangle(cornerRadius: 9))
            .background(selected ? accent.opacity(0.11) : .clear, in: RoundedRectangle(cornerRadius: 9))
        }
        .buttonStyle(.plain)
    }

    private var spaceSubtitle: String {
        switch store.space {
        case .normal: "Tu historial habitual de copias."
        case .ghost: "Un historial aparte para tus copias Fantasma."
        case .flash: "Esta copia desaparece después de 60 segundos."
        case .privateSession: "Cifrado localmente. Solo tú puedes desbloquearlo."
        }
    }

    private var emptyHistoryHint: String {
        switch store.space {
        case .normal: "Copia texto con ⌘C para guardarlo aquí."
        case .ghost: "Cambia a Fantasma y copia para guardar aquí."
        case .flash: "Activa Flash para guardar una copia por 60 segundos."
        case .privateSession: "Confirma con Touch ID para consultar este espacio."
        }
    }

    private func sectionHeading(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 12))
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle(title, isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
                .accessibilityLabel(title)
        }
        .frame(maxWidth: .infinity, minHeight: 30)
        .contentShape(Rectangle())
    }

    private func modeCard(_ space: ClipboardSpace, description: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Group {
                    if space == .ghost {
                        GhostMark(color: tint, size: 17)
                    } else {
                        Image(systemName: space.icon).font(.system(size: 14, weight: .semibold)).foregroundStyle(tint)
                    }
                }.frame(width: 30, height: 30).background(tint.opacity(0.11), in: RoundedRectangle(cornerRadius: 9))
                Text(space.rawValue).font(.system(size: 13, weight: .semibold))
            }
            Text(description)
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 85, alignment: .leading)
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(tint.opacity(0.13), lineWidth: 1))
    }

    private func clearButton(_ title: String, space: ClipboardSpace) -> some View {
        Button("Borrar \(title)") { store.clearAll(space) }
            .controlSize(.small)
            .tint(space == .privateSession || space == .flash ? .red : .primary)
    }

    private func shortcut(_ title: String, _ keys: String, _ detail: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer()
            Text(keys).font(.system(size: 14, weight: .medium, design: .monospaced)).padding(8)
                .background(.background, in: RoundedRectangle(cornerRadius: 7))
        }
    }
}
