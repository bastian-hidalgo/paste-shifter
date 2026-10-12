import SwiftUI
#if canImport(ClipboardCore)
import ClipboardCore
#endif
import Combine

private let ink = Color.primary
private let accent = Color(red: 0.52, green: 0.20, blue: 0.92)

private final class PickerClock: ObservableObject {
    @Published var now = Date()
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
}

struct PickerView: View {
    static let bubbleWidth: CGFloat = 360
    static let bubbleHeight: CGFloat = 44
    static let animationPadding: CGFloat = 24
    static let width = bubbleWidth + animationPadding * 2
    static let height = bubbleHeight + animationPadding * 2
    @ObservedObject var store: ClipboardStore
    @ObservedObject var motion: PickerMotion
    @Environment(\.colorScheme) private var colorScheme
    @ObservedObject private var clock = PickerClock()
    let paste: (Clip) -> Void

    var body: some View {
        let clips = store.filtered
        let selected = clips.firstIndex { $0.id == store.highlightedID } ?? 0
        return HStack(spacing: 8) {
            Group {
                if store.space == .ghost {
                    GhostMark(color: accent, size: 19)
                } else {
                    Image(systemName: store.space.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(store.space == .flash ? Color.yellow : .primary.opacity(0.8))
                }
            }
            .frame(width: 30, height: 30)
            .background(.primary.opacity(0.045), in: Circle())
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
            .contentShape(Rectangle())
            .onTapGesture {
                if Distribution.isAppStore, let clip = store.highlighted { paste(clip) }
            }
            .help(Distribution.isAppStore ? "Clic para copiar; después pulsa ⌘V en la app de destino." : "")
            if store.space == .flash, store.showFlashTimer, let expiry = store.flashExpiresAt {
                Text("\(max(0, Int(expiry.timeIntervalSince(clock.now).rounded(.up))))s")
                    .font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.yellow)
                    .frame(minWidth: 24)
            }
            if let clip = store.highlighted,
               let index = store.filtered.firstIndex(where: { $0.id == clip.id }) {
                Rectangle().fill(.primary.opacity(0.08)).frame(width: 1, height: 16)
                Text("\(index + 1)/\(store.filtered.count)")
                    .font(.system(size: 10, design: .monospaced)).monospacedDigit()
                    .foregroundStyle(.secondary)
                Image(systemName: "return")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 27, height: 27)
                    .background(Color.purple.opacity(0.62), in: Circle())
            }
            if store.space == .privateSession {
                Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary).frame(width: 18, height: 26).help("Guardar el portapapeles en Privado")
            }
            GhostMark(color: store.space == .ghost ? accent : .secondary, size: 18)
                .frame(width: 18, height: 26).help("Espacio Fantasma")
        }
        .padding(.horizontal, 8).frame(width: Self.bubbleWidth, height: Self.bubbleHeight)
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
        .scaleEffect(motion.scale)
        .opacity(motion.opacity)
        .padding(Self.animationPadding)
        .animation(.snappy(duration: 0.16), value: store.highlightedID)
        .onReceive(clock.timer) { clock.now = $0 }
        .accessibilityLabel(store.highlighted.map { "\(Distribution.isAppStore ? "Copiar" : "Pegar"): \($0.compactPreview)" } ?? "Historial vacío")
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
                    settingsToggle("Pegar al soltar ⌥ y ⇧", isOn: $store.pasteOnRelease)
                    Text(store.pasteOnRelease
                         ? "Mantén ⌥⇧ al abrir el historial, elige con el scroll y suelta ambos modificadores para pegar. Esc cancela."
                         : "Elige con el scroll y haz clic para pegar. También puedes usar Enter.")
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
                    settingsToggle("Pausar captura del portapapeles", isOn: $store.paused)
                    settingsToggle("Sonido al activar Privado", isOn: $store.privateSoundEnabled)
                    settingsToggle("Sonido spooky al activar Fantasma", isOn: $store.ghostSoundEnabled)
                    settingsToggle("Sonido al activar Flash", isOn: $store.flashSoundEnabled)
                    settingsToggle("Mostrar contador de Flash", isOn: $store.showFlashTimer)
                    settingsToggle(Distribution.isAppStore ? "Mostrar indicador al copiar" : "Mostrar LED al copiar y pegar", isOn: $store.showActivity)
                }
                Text("Privado se bloquea al cambiar de espacio y vuelve a pedir autenticación cuando ingresas. Flash elimina su copia al minuto si aún está en el portapapeles.")
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
                    Text("El historial Normal vive solo en memoria y se vacía al cerrar la app.")
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
                        Button("Copiar selección") { store.write(clip) }
                            .buttonStyle(.borderedProminent).tint(accent)
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
