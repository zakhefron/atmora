import AppKit
import SwiftUI

/// SwiftUI supplies the interface, but an AppKit-owned window gives Atmora
/// the exact menu-bar-utility lifecycle it needs: one persistent window, close
/// means hide, and a reliable reference for the global shortcut.
@MainActor
final class MainWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow
    var onVisibilityChanged: ((Bool) -> Void)?

    private var lastReportedVisibility = false
    private var observers: [NSObjectProtocol] = []

    init(rootView: AnyView) {
        let contentRect = NSRect(x: 0, y: 0, width: 940, height: 730)
        window = NSWindow(
            contentRect: contentRect,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.title = "Atmora"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.animationBehavior = .documentWindow
        window.minSize = NSSize(width: 800, height: 640)
        window.collectionBehavior = [.fullScreenPrimary]
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = true
        window.delegate = self

        let hosting = NSHostingView(rootView: rootView)
        hosting.wantsLayer = true
        window.contentView = hosting

        window.setFrameAutosaveName("AtmoraMainWindow")
        if !window.setFrameUsingName("AtmoraMainWindow") {
            window.center()
        }

        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didHideNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        })
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didUnhideNotification,
            object: NSApp,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.updateVisibility() }
        })
    }

    deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var isVisible: Bool {
        window.isVisible && !window.isMiniaturized
    }

    func show() {
        if NSApp.isHidden {
            NSApp.unhide(nil)
        }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.async { [weak self] in
            self?.updateVisibility()
        }
    }

    func hide() {
        window.orderOut(nil)
        updateVisibility()
    }

    func applyAppearance(_ appearance: NSAppearance?) {
        window.appearance = appearance
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hide()
        return false
    }

    func windowDidMiniaturize(_ notification: Notification) {
        updateVisibility()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        updateVisibility()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateVisibility()
    }

    func windowDidBecomeKey(_ notification: Notification) {
        updateVisibility()
    }

    private func updateVisibility() {
        let visible = window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
            && !NSApp.isHidden
        if visible != lastReportedVisibility {
            lastReportedVisibility = visible
            onVisibilityChanged?(visible)
        }
    }
}
