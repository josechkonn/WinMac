import AppKit
import ServiceManagement
import WinMacCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let hotkeyManager = HotkeyManager()
    private let snapCoordinator = SnapCoordinator()
    private var permissionTimer: Timer?
    private var isPaused = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let bundleID = Bundle.main.bundleIdentifier {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            if running.count > 1 {
                NSApp.terminate(nil)
                return
            }
        }

        setupStatusItem()
        startHotkeys()

        // Only check/prompt silently once on launch if not yet trusted; never spam System Settings on hotkeys
        if !AXWindowController.isAccessibilityTrusted(prompt: false) {
            _ = AXWindowController.isAccessibilityTrusted(prompt: true)
            startPermissionPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        hotkeyManager.stop()
    }

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        updateStatusIcon(for: item)

        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func updateStatusIcon(for item: NSStatusItem?) {
        guard let button = item?.button else { return }
        let trusted = AXWindowController.isAccessibilityTrusted(prompt: false)
        let symbolName: String
        if !trusted {
            symbolName = "exclamationmark.triangle"
        } else if isPaused {
            symbolName = "rectangle.split.2x2"
        } else {
            symbolName = "rectangle.split.2x2.fill"
        }

        if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "WinMac") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "WM"
        }
        button.alphaValue = isPaused ? 0.5 : 1.0
    }

    private func startHotkeys() {
        hotkeyManager.start { [weak self] action in
            guard let self else { return }
            guard AXWindowController.isAccessibilityTrusted(prompt: false) else {
                self.updateStatusIcon(for: self.statusItem)
                return
            }
            self.snapCoordinator.perform(action)
        }
    }

    private func startPermissionPolling() {
        permissionTimer?.invalidate()
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if AXWindowController.isAccessibilityTrusted(prompt: false) {
                    self.permissionTimer?.invalidate()
                    self.permissionTimer = nil
                    self.updateStatusIcon(for: self.statusItem)
                }
            }
        }
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let trusted = AXWindowController.isAccessibilityTrusted(prompt: false)
        updateStatusIcon(for: statusItem)

        let statusTitle: String
        if !trusted {
            statusTitle = "WinMac — Falta permiso de Accesibilidad"
        } else if isPaused {
            statusTitle = "WinMac — Pausado"
        } else {
            statusTitle = "WinMac — Activo"
        }
        let headerItem = NSMenuItem(title: statusTitle, action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        if !trusted {
            let grantItem = NSMenuItem(
                title: "Abrir Ajustes de Accesibilidad…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            grantItem.target = self
            menu.addItem(grantItem)
        }

        menu.addItem(.separator())

        let shortcutsHeader = NSMenuItem(title: "Atajos (Control + Option)", action: nil, keyEquivalent: "")
        shortcutsHeader.isEnabled = false
        menu.addItem(shortcutsHeader)

        let cheatsheet = [
            "⌃⌥ ← / →   Mitad / Restaurar / Monitor",
            "⌃⌥ ↑       Cuadrante superior / Maximizar",
            "⌃⌥ ↓       Cuadrante inferior / Minimizar",
            "⌃⌥ ⌫       Restaurar tamaño original",
            "⌃⌥ C       Centrar ventana"
        ]
        for line in cheatsheet {
            let item = NSMenuItem(title: line, action: nil, keyEquivalent: "")
            item.isEnabled = false
            menu.addItem(item)
        }

        menu.addItem(.separator())

        let pauseItem = NSMenuItem(
            title: isPaused ? "Reanudar atajos" : "Pausar atajos",
            action: #selector(togglePause),
            keyEquivalent: ""
        )
        pauseItem.target = self
        menu.addItem(pauseItem)

        let loginItem = NSMenuItem(
            title: "Iniciar al encender macOS",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Salir de WinMac", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    // MARK: - Actions

    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        startPermissionPolling()
    }

    @objc private func togglePause() {
        isPaused.toggle()
        snapCoordinator.isEnabled = !isPaused
        updateStatusIcon(for: statusItem)
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSLog("WinMac: Could not update login item status: %@", error.localizedDescription)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}
