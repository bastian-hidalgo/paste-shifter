import AppKit
import SwiftUI
#if canImport(ClipboardCore)
import ClipboardCore
#endif

final class PickerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private final class OrbitalSendRequest: NSObject {
        let clip: Clip
        let deviceID: UUID
        init(clip: Clip, deviceID: UUID) { self.clip = clip; self.deviceID = deviceID }
    }

    let store = ClipboardStore()
    let orbital = OrbitalCoordinator()
    private let permission = AccessibilityPermission()
    private let loginItem = LoginItemSettings()
    private let hotKeys = HotKeys()
    private var statusItem: NSStatusItem!
    private var panel: PickerPanel!
    private var settingsWindow: NSWindow?
    private var keyMonitor: Any?
    private var scrollMonitor: Any?
    private var pasteMonitor: Any?
    private var modifierMonitor: Any?
    private var releaseSelection = ReleaseSelection()
    private var scrollSelection = ScrollSelection()
    private let globalScroll = GlobalScrollMonitor()
    private let pickerAnimator = PickerAnimator()
    private var pickerOpen = false
    private let activityIndicator = ActivityIndicator()
    private var suppressPasteIndicatorUntil: TimeInterval = 0
    private var lastPermissionCheck: TimeInterval = 0
    private var clickMonitor: Any?
    private var localClickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var target: NSRunningApplication?
    private var lastExternalApp: NSRunningApplication?
    private var returningFromPrivacy = false
    private var sawPrivacySettings = false
    private var flashStatusActive = false
    private var lastFlashStatusSecond: Int?
    private var lastFlashTimerVisible: Bool?

    func applicationDidFinishLaunching(_ notification: Notification) {
        permission.onOpenPrivacy = { [weak self] in self?.returningFromPrivacy = true }
        orbital.configure(store: store)
        installApplicationMenu()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateModeStatus()
        statusItem.button?.toolTip = "Paste Shifter · ⌥⇧V"
        let menu = NSMenu()
        menu.delegate = self
        add("Abrir historial", action: #selector(showHistory), to: menu)
        add(Distribution.isAppStore ? "Copiar última copia" : "Pegar última copia", action: #selector(quickPaste), to: menu)
        add("Guardar portapapeles en Privado", action: #selector(saveCurrentToPrivate), to: menu)
        add("Eliminar elemento seleccionado", action: #selector(removeSelected), to: menu)
        add("Guardar copia seleccionada en Fantasma", action: #selector(saveSelectedToGhost), to: menu)
        menu.addItem(.separator())
        for space in ClipboardSpace.allCases {
            let item = NSMenuItem(title: "Modo \(space.rawValue)", action: #selector(chooseSpace(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = space.rawValue; menu.addItem(item)
        }
        menu.addItem(.separator())
        add("Pausar captura", action: #selector(togglePause), to: menu)
        add("Vaciar historial normal", action: #selector(clearNormal), to: menu)
        add("Vaciar historial Fantasma", action: #selector(clearGhost), to: menu)
        add("Borrar historial Privado", action: #selector(clearPrivate), to: menu)
        add("Ajustes…", action: #selector(showSettings), to: menu)
        menu.addItem(.separator())
        add("Salir de Paste Shifter", action: #selector(quit), to: menu)
        statusItem.menu = menu

        panel = PickerPanel(contentRect: NSRect(x: 0, y: 0, width: PickerView.width, height: PickerView.height), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.backgroundColor = .clear; panel.isOpaque = false; panel.hasShadow = false
        panel.hidesOnDeactivate = false; panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false; panel.delegate = self
        panel.title = "Historial — Paste Shifter"
        let pickerHosting = NSHostingView(rootView: PickerView(store: store, orbital: orbital,
                                                               motion: pickerAnimator.motion,
                                                               sendToAndroid: { [weak self] in self?.sendWidgetSelectionToAndroid() },
                                                               paste: { [weak self] clip in
            guard let self, self.pickerOpen else { return }
            self.paste(clip)
        }))
        pickerHosting.sizingOptions = []
        pickerHosting.frame = NSRect(x: 0, y: 0, width: PickerView.width, height: PickerView.height)
        panel.contentView = pickerHosting
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            guard let self, self.pickerOpen else { return event }
            if event.type == .flagsChanged {
                if !Distribution.isAppStore { self.finishReleaseSelection(modifiers: event.modifierFlags) }
                return event
            }
            guard event.window === self.panel else { return event }
            switch event.keyCode {
            case 125: self.store.move(1)
            case 126: self.store.move(-1)
            case 36, 76: if let clip = self.store.highlighted { self.paste(clip) }
            case 53: self.dismiss(feedback: true)
            default: return event
            }
            return nil
        }
        #if !APP_STORE
        modifierMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.finishReleaseSelection(modifiers: event.modifierFlags)
        }
        #endif
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.pickerOpen, event.window === self.panel else { return event }
            // Shift can turn a wheel gesture into horizontal scrolling.
            let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
            if let step = self.scrollSelection.step(delta: Double(delta), precise: event.hasPreciseScrollingDeltas, momentum: !event.momentumPhase.isEmpty, time: event.timestamp) {
                self.store.move(step)
            }
            // Consume scrolling within the card; the document underneath stays still.
            return nil
        }
        #if !APP_STORE
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self, self.pickerOpen else { return }
            if event.type == .rightMouseDown || !self.globalScroll.isCapturing { self.dismiss(feedback: true) }
        }
        #endif
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, self.pickerOpen, event.window !== self.panel { self.dismiss() }
            return event
        }
        lastExternalApp = NSWorkspace.shared.frontmostApplication
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            self.permission.refresh()
            if self.returningFromPrivacy, app.bundleIdentifier == "com.apple.systempreferences" {
                self.sawPrivacySettings = true
            } else if self.returningFromPrivacy, self.sawPrivacySettings {
                self.returningFromPrivacy = false; self.sawPrivacySettings = false
                DispatchQueue.main.async { [weak self] in self?.showSettings() }
            }
            guard app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            self.lastExternalApp = app
            self.dismiss()
        }
        hotKeys.onPress = { [weak self] id in
            switch id {
            case 1: self?.quickPaste()
            case 2: self?.showHistoryFromShortcut()
            case 3: self?.captureFlash()
            default: break
            }
        }
        if !CommandLine.arguments.contains("--demo") { hotKeys.register() }
        if CommandLine.arguments.contains("--demo") {
            store.historyDemo()
            showHistory()
        } else {
            store.onCopy = { [weak self] in
                guard let self, self.store.showActivity else { return }
                self.activityIndicator.flash(.copy, target: self.externalTarget())
            }
            store.onTick = { [weak self] in
                self?.updatePasteMonitor()
                self?.updateFlashStatus()
                self?.updateModeStatus()
            }
            updatePasteMonitor()
            store.start()
        }
        if !CommandLine.arguments.contains("--demo"), (!permission.granted || !UserDefaults.standard.bool(forKey: "hasLaunched")) {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        }
    }

    @objc private func chooseSpace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let space = ClipboardSpace(rawValue: raw) else { return }
        store.switchSpace(space == store.space && space != .normal ? .normal : space)
        updateModeStatus()
        showHistory()
    }

    @objc private func chooseApplicationSpace(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let space = ClipboardSpace(rawValue: raw) else { return }
        store.switchSpace(space == store.space && space != .normal ? .normal : space)
        updateModeStatus()
        showHistory()
    }

    private func updateModeStatus() {
        guard let button = statusItem?.button else { return }
        if store.space == .normal {
            button.image = BrandIcon.template
            button.image?.isTemplate = true
            button.title = ""
            button.toolTip = "Paste Shifter · ⌥⇧V"
            button.contentTintColor = nil
            statusItem.length = NSStatusItem.squareLength
            return
        }
        let badge: String?
        switch store.space {
        case .normal: badge = nil
        case .privateSession: badge = "lock.fill"
        case .ghost: badge = nil
        case .flash: badge = "bolt.fill"
        }
        guard let badge else {
            let combined = NSImage(size: NSSize(width: 31, height: 18), flipped: false) { _ in
                BrandIcon.template.draw(in: NSRect(x: 0, y: 1, width: 17, height: 16))
                BrandIcon.ghost.draw(in: NSRect(x: 18, y: 1, width: 11, height: 13))
                return true
            }
            combined.isTemplate = true
            button.image = combined
            button.image?.isTemplate = true
            button.title = ""
            button.toolTip = "Paste Shifter · modo Fantasma · ⌥⇧V"
            statusItem.length = NSStatusItem.variableLength
            return
        }
        guard let badgeImage = NSImage(systemSymbolName: badge, accessibilityDescription: store.space.rawValue) else {
            button.image = BrandIcon.template
            button.image?.isTemplate = true
            button.title = ""
            button.toolTip = "Paste Shifter · ⌥⇧V"
            statusItem.length = NSStatusItem.squareLength
            return
        }
        let combined = NSImage(size: NSSize(width: 31, height: 18), flipped: false) { rect in
            BrandIcon.template.draw(in: NSRect(x: 0, y: 1, width: 17, height: 16))
            let symbol = badgeImage.withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .bold)) ?? badgeImage
            symbol.draw(in: NSRect(x: 18, y: 0, width: 12, height: 12))
            return true
        }
        combined.isTemplate = true
        button.image = combined
        button.image?.isTemplate = true
        if store.space == .flash, store.showFlashTimer, let expiry = store.flashExpiresAt {
            button.title = " \(max(0, Int(expiry.timeIntervalSinceNow.rounded(.up))))s"
            button.contentTintColor = .systemYellow
        } else {
            button.title = ""
            button.contentTintColor = nil
        }
        button.toolTip = "Paste Shifter · modo \(store.space.rawValue) · ⌥⇧V"
        statusItem.length = NSStatusItem.variableLength
    }

    private func captureFlash() {
        if Distribution.isAppStore {
            guard let text = NSPasteboard.general.string(forType: .string),
                  !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { NSSound.beep(); return }
            store.beginFlash(text: text)
            showHistory()
            return
        }
        guard let source = externalTarget() else { NSSound.beep(); return }
        target = source
        let clipboard = NSPasteboard.general
        let previousChangeCount = clipboard.changeCount
        PasteService.copy(from: source) { [weak self] success in
            guard let self, success else { NSSound.beep(); return }
            self.waitForFlashClipboardChange(clipboard, previousChangeCount: previousChangeCount,
                                             deadline: Date().addingTimeInterval(1.5))
        }
    }

    private func waitForFlashClipboardChange(_ clipboard: NSPasteboard, previousChangeCount: Int, deadline: Date) {
        if clipboard.changeCount != previousChangeCount,
           let text = clipboard.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            store.beginFlash(text: text)
            if pickerOpen { dismiss() }
            showHistory()
            return
        }
        guard Date() < deadline else { NSSound.beep(); return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.waitForFlashClipboardChange(clipboard, previousChangeCount: previousChangeCount, deadline: deadline)
        }
    }

    private func updateFlashStatus() {
        guard let expiry = store.flashExpiresAt else {
            if flashStatusActive {
                statusItem.button?.contentTintColor = nil
                flashStatusActive = false
                lastFlashStatusSecond = nil
                lastFlashTimerVisible = nil
                updateModeStatus()
            }
            return
        }
        if !flashStatusActive {
            flashStatusActive = true
            updateModeStatus()
        }
        let visible = store.showFlashTimer
        let seconds = max(0, Int(expiry.timeIntervalSinceNow.rounded(.up)))
        if seconds != lastFlashStatusSecond || visible != lastFlashTimerVisible {
            if visible {
                statusItem.button?.attributedTitle = NSAttributedString(
                    string: " \(seconds)s",
                    attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 11, weight: .semibold)]
                )
            } else {
                statusItem.button?.title = ""
            }
            lastFlashStatusSecond = seconds
            lastFlashTimerVisible = visible
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationWillTerminate(_ notification: Notification) {
        orbital.endPairing()
        orbital.transportShutdown()
        store.prepareToQuit()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showSettings() }
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        permission.refresh()
        loginItem.refresh()
    }

    private func updatePasteMonitor() {
        #if APP_STORE
        return
        #else
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastPermissionCheck >= 2 else { return }
        lastPermissionCheck = now
        permission.refresh()
        guard store.showActivity, permission.granted else {
            if let pasteMonitor { NSEvent.removeMonitor(pasteMonitor); self.pasteMonitor = nil }
            return
        }
        guard pasteMonitor == nil else { return }
        pasteMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.store.showActivity, !event.isARepeat,
                  event.modifierFlags.intersection([.command, .option, .control]) == .command else { return }
            if event.keyCode == 8 {
                // Read the resulting clipboard, never record the user's keystrokes.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.store.capture() }
            } else if event.keyCode == 9, ProcessInfo.processInfo.systemUptime > self.suppressPasteIndicatorUntil {
                self.activityIndicator.flash(.paste, target: self.externalTarget())
            }
        }
        #endif
    }

    private func installApplicationMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu(); appItem.submenu = appMenu
        let openHistory = NSMenuItem(title: "Abrir historial", action: #selector(showHistory), keyEquivalent: "")
        openHistory.target = self; appMenu.addItem(openHistory)
        let modeItem = NSMenuItem(title: "Cambiar modo", action: nil, keyEquivalent: "")
        let modeMenu = NSMenu(title: "Cambiar modo")
        modeMenu.delegate = self
        for space in ClipboardSpace.allCases {
            let item = NSMenuItem(title: space.rawValue, action: #selector(chooseApplicationSpace(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = space.rawValue; modeMenu.addItem(item)
        }
        modeItem.submenu = modeMenu; appMenu.addItem(modeItem)
        appMenu.addItem(.separator())
        let quit = NSMenuItem(title: "Salir de Paste Shifter", action: #selector(quit), keyEquivalent: "q")
        quit.target = self; appMenu.addItem(quit)
        let fileItem = NSMenuItem(title: "Archivo", action: nil, keyEquivalent: ""); main.addItem(fileItem)
        let file = NSMenu(title: "Archivo"); fileItem.submenu = file
        file.addItem(withTitle: "Cerrar", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        let editItem = NSMenuItem(title: "Edición", action: nil, keyEquivalent: ""); main.addItem(editItem)
        let edit = NSMenu(title: "Edición"); editItem.submenu = edit
        for (title, action, key) in [("Deshacer", "undo:", "z"), ("Cortar", "cut:", "x"), ("Copiar", "copy:", "c"), ("Pegar", "paste:", "v"), ("Seleccionar todo", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        NSApp.mainMenu = main
    }

    private func add(_ title: String, action: Selector, to menu: NSMenu) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; menu.addItem(item)
    }

    private func externalTarget() -> NSRunningApplication? {
        let app = NSWorkspace.shared.frontmostApplication
        return app?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? lastExternalApp : app
    }

    @objc func showHistory() {
        if pickerOpen { dismiss(feedback: true); return }
        target = externalTarget()
        store.prepare()
        if store.space == .privateSession, !store.privateUnlocked { store.unlockPrivate() }
        scrollSelection.reset()
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let origin = WidgetPlacement.nearMouse(mouse, size: CGSize(width: PickerView.bubbleWidth, height: PickerView.bubbleHeight), in: visible)
        panel.setFrameOrigin(NSPoint(x: origin.x - PickerView.animationPadding, y: origin.y - PickerView.animationPadding))
        pickerOpen = true
        pickerAnimator.show(panel)
        if !CommandLine.arguments.contains("--demo") {
            store.globalScrollUnavailable = !globalScroll.start(onStep: { [weak self] step in
                guard let self, self.pickerOpen else { return }
                self.store.move(step)
            }, onConfirm: { [weak self] point in
                guard let self, self.pickerOpen else { return }
                let bubbleRect = self.panel.frame.insetBy(dx: PickerView.animationPadding, dy: PickerView.animationPadding)
                if bubbleRect.contains(point) {
                    let localX = point.x - bubbleRect.minX
                    if localX < 42 {
                        self.cycleSpace(); return
                    }
                    if self.store.space == .privateSession,
                       localX > PickerView.bubbleWidth - 57, localX < PickerView.bubbleWidth - 25 {
                        self.store.saveCurrentToPrivate(); return
                    }
                    if localX > PickerView.bubbleWidth - 22 {
                        self.sendWidgetSelectionToAndroid(); return
                    }
                }
                // Outside the two mode controls, every click pastes the selection.
                if let clip = self.store.highlighted { self.paste(clip) } else { self.dismiss(feedback: true) }
            })
        }
        NSAccessibility.post(element: panel!, notification: .layoutChanged)
    }

    private func showHistoryFromShortcut() {
        let wasVisible = pickerOpen
        showHistory()
        if !Distribution.isAppStore, !wasVisible, pickerOpen, store.pasteOnRelease {
            releaseSelection.arm()
            // Also covers a very fast release while obtaining the caret bounds.
            finishReleaseSelection(modifiers: NSEvent.modifierFlags)
        }
    }

    private func sendWidgetSelectionToAndroid() {
        guard let clip = store.highlighted,
              orbital.mayManuallyShare(space: store.space, text: clip.text) else {
            NSSound.beep()
            return
        }
        let devices = orbital.pairedDevices
        guard !devices.isEmpty else { NSSound.beep(); return }
        if devices.count == 1, let device = devices.first {
            orbital.sendManually(clip.text, from: store.space, to: device.id)
            return
        }
        let menu = NSMenu()
        for device in devices {
            let item = NSMenuItem(title: device.name, action: #selector(sendWidgetClipToDevice(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = OrbitalSendRequest(clip: clip, deviceID: device.id)
            menu.addItem(item)
        }
        menu.popUp(positioning: nil,
                   at: NSPoint(x: PickerView.animationPadding + PickerView.bubbleWidth - 8,
                               y: PickerView.animationPadding + PickerView.bubbleHeight - 8),
                   in: panel.contentView)
    }

    @objc private func sendWidgetClipToDevice(_ sender: NSMenuItem) {
        guard let request = sender.representedObject as? OrbitalSendRequest else { return }
        orbital.sendManually(request.clip.text, from: store.space, to: request.deviceID)
    }

    private func finishReleaseSelection(modifiers: NSEvent.ModifierFlags) {
        guard !Distribution.isAppStore, store.pasteOnRelease, pickerOpen,
              releaseSelection.commit(optionHeld: modifiers.contains(.option), shiftHeld: modifiers.contains(.shift)) else { return }
        if let clip = store.highlighted { paste(clip) } else { dismiss() }
    }

    @objc func quickPaste() {
        if !pickerOpen { target = externalTarget() }
        store.capture()
        guard let clip = store.visibleHistory.latest else { showHistory(); return }
        paste(clip)
    }

    private func paste(_ clip: Clip) {
        if CommandLine.arguments.contains("--demo") { store.select(clip); dismiss(); return }
        if Distribution.isAppStore {
            store.write(clip)
            dismiss()
            if store.showActivity { activityIndicator.flash(.copy, target: nil) }
            return
        }
        let destination = target
        dismiss()
        store.write(clip)
        permission.refresh()
        guard permission.granted else { showSettings(); return }
        guard let destination else { NSSound.beep(); return }
        suppressPasteIndicatorUntil = ProcessInfo.processInfo.systemUptime + 1
        PasteService.paste(into: destination) { [weak self] success in
            if success, let self, self.store.showActivity {
                self.activityIndicator.flash(.paste, target: destination)
            } else if !success { NSSound.beep() }
        }
    }

    func dismiss(feedback: Bool = false) {
        let wasOpen = pickerOpen
        pickerOpen = false
        releaseSelection.cancel()
        globalScroll.stop()
        if wasOpen {
            pickerAnimator.hide(panel)
            if feedback, store.showActivity { activityIndicator.flash(.close, target: target) }
        }
    }
    func windowDidResignKey(_ notification: Notification) {
        if notification.object as? NSWindow === panel { dismiss() }
    }
    @objc func togglePause(_ sender: NSMenuItem) {
        store.paused.toggle(); sender.title = store.paused ? "Reanudar captura" : "Pausar captura"
        statusItem.button?.appearsDisabled = store.paused
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.first(where: { $0.action == #selector(togglePause) })?.title = store.paused ? "Reanudar captura" : "Pausar captura"
        statusItem.button?.appearsDisabled = store.paused
        for item in menu.items {
            if let raw = item.representedObject as? String, let space = ClipboardSpace(rawValue: raw) {
                item.state = space == store.space ? .on : .off
            }
            if item.submenu != nil {
                for modeItem in item.submenu!.items {
                    if let raw = modeItem.representedObject as? String, let space = ClipboardSpace(rawValue: raw) {
                        modeItem.state = space == store.space ? .on : .off
                    }
                }
            }
        }
        updateModeStatus()
    }
    @objc func clearHistory() { store.clearAll(.normal) }
    @objc private func removeSelected() { store.removeHighlighted() }
    @objc private func saveSelectedToGhost() { store.saveHighlightedToGhost() }
    @objc private func saveCurrentToPrivate() {
        store.switchSpace(.privateSession)
        store.saveCurrentToPrivate()
    }
    private func cycleSpace() {
        // Tapping the active mode icon is an exit gesture. Normal enters Ghost;
        // other modes return to Normal rather than unexpectedly cycling onward.
        store.switchSpace(store.space == .normal ? .ghost : .normal)
    }
    @objc private func clearNormal() { store.clearAll(.normal) }
    @objc private func clearGhost() { store.clearAll(.ghost) }
    @objc private func clearPrivate() { store.clearAll(.privateSession) }
    @objc func quit() { NSApp.terminate(nil) }

    @objc func showSettings() {
        dismiss()
        permission.refresh()
        if settingsWindow == nil {
            let height = min(CGFloat(730), (NSScreen.main?.visibleFrame.height ?? 830) - 80)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: height), styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Paste Shifter"; window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.canHide = false
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            let hosting = NSHostingView(rootView: SettingsView(store: store, orbital: orbital, permission: permission, loginItem: loginItem, shortcutFailures: hotKeys.failures,
                                                               appIcon: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath), windowHeight: height,
                                                               onSwitchSpace: { [weak self] space in self?.switchSpaceFromSettings(space) }))
            // A changing SwiftUI permission section must not resize the NSWindow
            // to an invalid intrinsic size or collapse it to its title bar.
            hosting.sizingOptions = []
            hosting.frame = NSRect(x: 0, y: 0, width: 1040, height: height)
            hosting.autoresizingMask = [.width, .height]
            window.contentView = hosting
            window.center(); settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func switchSpaceFromSettings(_ space: ClipboardSpace) {
        store.switchSpace(space)
        store.prepare()
    }
}
