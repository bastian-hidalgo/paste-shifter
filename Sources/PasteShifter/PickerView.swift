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
        .accessibilityLabel(store.highlighted.map { "Pegar: \($0.compactPreview)" } ?? "Historial vacío")
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

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 14) {
                Image(nsImage: appIcon).resizable().scaledToFit().frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Paste Shifter").font(.system(size: 22, weight: .bold))
                    Text("Tu portapapeles, ordenado a tu manera.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 12) {
                sectionHeading("Elige cómo guardar", subtitle: "Cada modo mantiene su propio historial.")
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], alignment: .leading, spacing: 10) {
                    modeCard(.normal, description: "Las copias con ⌘C aparecen aquí automáticamente.", tint: .blue)
                    modeCard(.ghost, description: "Un historial separado. Las copias hechas aquí se quedan aparte.", tint: accent)
                    modeCard(.flash, description: "⌥⇧C captura la selección y la elimina en 60 segundos.", tint: .orange)
                    modeCard(.privateSession, description: "Pulsa + para guardar. Se cifra y pide Touch ID al entrar.", tint: .green)
                }
                Text("Cambia de modo desde el menú de Paste Shifter en la barra superior del Mac.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Atajos", subtitle: "Abre y pega sin interrumpir lo que estás haciendo.")
                VStack(spacing: 12) {
                    shortcut("Pegar la última copia", "⌥ V", "Pega lo último que copiaste con ⌘C.")
                    Divider()
                    shortcut("Elegir del historial", "⌥ ⇧ V", "Desplázate por las copias y selecciónalas.")
                    Divider()
                    shortcut("Captura Flash", "⌥ ⇧ C", "Guarda la selección activa por 60 segundos.")
                }.padding(16).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                Toggle("Pegar al soltar ⌥ y ⇧", isOn: $store.pasteOnRelease)
                    .toggleStyle(.switch).font(.system(size: 12))
                Text(store.pasteOnRelease
                     ? "Mantén ⌥⇧ al abrir el historial, elige con el scroll y suelta ambos modificadores para pegar. Esc cancela."
                     : "Elige con el scroll y haz clic para pegar. También puedes usar Enter.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                sectionHeading("Privacidad y captura")
                VStack(alignment: .leading, spacing: 11) {
                    Toggle("Pausar captura del portapapeles", isOn: $store.paused)
                    Toggle("Sonido al activar Privado", isOn: $store.privateSoundEnabled)
                    Toggle("Sonido spooky al activar Fantasma", isOn: $store.ghostSoundEnabled)
                    Toggle("Sonido al activar Flash", isOn: $store.flashSoundEnabled)
                    Toggle("Mostrar contador de Flash", isOn: $store.showFlashTimer)
                    Toggle("Mostrar LED al copiar y pegar", isOn: $store.showActivity)
                }.toggleStyle(.switch).font(.system(size: 12))
                Text("Privado se bloquea al salir del modo. Si cierras y reabres el widget sin salir, no vuelve a pedir autenticación. Flash limpia su copia al cumplirse el minuto si sigue en el portapapeles.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let error = store.privateError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                }
            }

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
                    Toggle("Abrir al iniciar sesión", isOn: Binding(get: { loginItem.enabled }, set: { loginItem.setEnabled($0) }))
                        .toggleStyle(.switch).font(.system(size: 12))
                    if loginItem.needsApproval {
                        Button("Abrir Ítems de inicio…") { loginItem.openSettings() }
                    }
                    if let error = loginItem.errorMessage {
                        Text(error).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(15).background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
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
            Text("Al cerrar Ajustes, Paste Shifter sigue disponible en la barra de menú.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .padding(24)
        .frame(width: 510)
    }

    private func sectionHeading(_ title: String, subtitle: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 15, weight: .semibold))
            if let subtitle {
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
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
        .background(.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 13))
        .overlay(RoundedRectangle(cornerRadius: 13).strokeBorder(tint.opacity(0.13), lineWidth: 1))
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
