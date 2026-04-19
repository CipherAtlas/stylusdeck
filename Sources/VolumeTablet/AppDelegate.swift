import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let state = ControlSurfaceState()
    private lazy var controller = ControlSurfaceController(state: state)
    private var windows: [OverlayWindow] = []
    private var keyEventMonitor: Any?
    private var isFullscreenTransitionInFlight = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let markImage = BrandAssets.markImage() {
            NSApp.applicationIconImage = markImage
        }
        installMenu()
        rebuildWindows()
        controller.start()
        installKeyMonitor()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller.stop()
        if let keyEventMonitor {
            NSEvent.removeMonitor(keyEventMonitor)
        }
    }

    @objc
    private func handleScreenParametersChange() {
        rebuildWindows()
    }

    private func installMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()

        appMenu.addItem(
            withTitle: "Quit StylusDeck",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )

        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)
        NSApp.mainMenu = mainMenu
    }

    private func rebuildWindows() {
        guard let screen = prioritizedScreens().first else {
            windows.forEach { $0.close() }
            windows.removeAll()
            return
        }

        if let window = windows.first {
            updateWindow(window, for: screen)
        } else {
            let window = makeWindow(for: screen)
            windows = [window]
        }

        activateAllWindows()
    }

    private func prioritizedScreens() -> [NSScreen] {
        guard let activeScreen = currentPointerScreen() else {
            return NSScreen.screens
        }

        return NSScreen.screens.sorted { lhs, rhs in
            if lhs == activeScreen { return true }
            if rhs == activeScreen { return false }
            return lhs.localizedName < rhs.localizedName
        }
    }

    private func currentPointerScreen() -> NSScreen? {
        let mouseLocation = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouseLocation, $0.frame, false) }
    }

    private func activateAllWindows() {
        for window in windows {
            window.makeKeyAndOrderFront(nil)
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
    }

    private func toggleFullscreen() {
        guard let window = windows.first else { return }
        activateAllWindows()
        window.toggleFullScreen(nil)
    }

    private func makeWindow(for screen: NSScreen) -> OverlayWindow {
        let window = OverlayWindow(screen: screen)
        let contentView = ControlSurfaceView(
            frame: NSRect(origin: .zero, size: screen.frame.size),
            screen: screen,
            state: state,
            controller: controller,
            onRequestFullscreen: { [weak self] in
                self?.toggleFullscreen()
            }
        )

        window.delegate = self
        window.contentView = contentView
        window.makeFirstResponder(contentView)
        window.makeKeyAndOrderFront(nil)
        return window
    }

    private func updateWindow(_ window: OverlayWindow, for screen: NSScreen) {
        guard !isFullscreenTransitionInFlight, !window.styleMask.contains(.fullScreen) else { return }
        window.setFrame(screen.frame, display: true)
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        isFullscreenTransitionInFlight = true
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        isFullscreenTransitionInFlight = false
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        isFullscreenTransitionInFlight = true
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        isFullscreenTransitionInFlight = false
        rebuildWindows()
    }

    private func installKeyMonitor() {
        keyEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }

            let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
            switch key {
            case "1":
                self.controller.navigate(to: .volume)
                return nil
            case "2":
                self.controller.navigate(to: .low)
                return nil
            case "3":
                self.controller.navigate(to: .mid)
                return nil
            case "4":
                self.controller.navigate(to: .high)
                return nil
            case "5":
                self.controller.toggleBank()
                return nil
            case "6":
                self.controller.centerCurrentRoute()
                return nil
            case "c":
                self.controller.centerCurrentRoute()
                return nil
            case "f":
                self.toggleFullscreen()
                self.state.update { $0.statusText = "Fullscreen" }
                return nil
            case "q":
                if event.modifierFlags.contains(.command) {
                    NSApp.terminate(nil)
                    return nil
                }
                return event
            default:
                if event.keyCode == 53 {
                    NSApp.terminate(nil)
                    return nil
                }
                return event
            }
        }
    }
}
