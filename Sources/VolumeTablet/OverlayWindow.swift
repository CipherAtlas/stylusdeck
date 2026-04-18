import AppKit

final class OverlayWindow: NSWindow {
    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        setFrame(screen.frame, display: true)
        title = "StylusDeck"
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        level = .normal
        collectionBehavior = [.fullScreenPrimary, .moveToActiveSpace, .managed]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = false
        isMovable = true
        isMovableByWindowBackground = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        setFrameAutosaveName("StylusDeckOverlay")
        minSize = NSSize(width: 900, height: 620)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
