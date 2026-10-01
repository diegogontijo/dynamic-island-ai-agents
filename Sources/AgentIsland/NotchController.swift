import AppKit
import SwiftUI

struct NotchGeometry: Equatable {
    var width: CGFloat
    var height: CGFloat
    var hasHardwareNotch: Bool

    static func detect(on screen: NSScreen) -> NotchGeometry {
        let top = screen.safeAreaInsets.top
        if top > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return NotchGeometry(width: screen.frame.width - left.width - right.width,
                                 height: top,
                                 hasHardwareNotch: true)
        }
        // External displays without a notch: use a notch-sized hit area in the menu bar.
        return NotchGeometry(width: 190, height: NSStatusBar.system.thickness, hasHardwareNotch: false)
    }
}

@MainActor
final class NotchViewModel: ObservableObject {
    @Published var isOpen = false
    @Published var notch = NotchGeometry(width: 190, height: 32, hasHardwareNotch: true)

    var openSize: CGSize { CGSize(width: 500, height: notch.height + 148) }

    var onOpenRequest: (() -> Void)?
}

/// Borderless panel that floats above the menu bar, sitting exactly over the notch.
final class NotchPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class NotchController {
    static let openAnimation = Animation.spring(response: 0.38, dampingFraction: 0.78)
    static let closeAnimation = Animation.spring(response: 0.32, dampingFraction: 0.9)

    let model = NotchViewModel()
    private let store: UsageStore
    private let panel: NotchPanel
    private var monitors: [Any] = []
    private var pendingClose: DispatchWorkItem?

    /// Room around the open panel for its outward top flares and drop shadow.
    private let openMargin = CGSize(width: 60, height: 24)

    init(store: UsageStore) {
        self.store = store
        panel = NotchPanel(contentRect: .zero,
                           styleMask: [.borderless, .nonactivatingPanel],
                           backing: .buffered,
                           defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.acceptsMouseMovedEvents = true

        let hosting = FirstMouseHostingView(rootView: NotchRootView(model: model, store: store))
        hosting.sizingOptions = []
        panel.contentView = hosting

        model.onOpenRequest = { [weak self] in self?.open() }

        layout()
        panel.orderFrontRegardless()
        installMonitors()

        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.layout() }
        }
    }

    var isOpen: Bool { model.isOpen }

    func toggle() { isOpen ? close() : open() }

    func open() {
        guard !model.isOpen else { return }
        pendingClose?.cancel()
        panel.setFrame(frame(open: true), display: true)
        // Let the window grow first so SwiftUI animates from the notch size.
        DispatchQueue.main.async {
            withAnimation(Self.openAnimation) { self.model.isOpen = true }
        }
        store.refreshIfStale()
    }

    func close() {
        guard model.isOpen else { return }
        pendingClose?.cancel()
        withAnimation(Self.closeAnimation) { model.isOpen = false }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.model.isOpen else { return }
            self.panel.setFrame(self.frame(open: false), display: true)
        }
    }

    private var screen: NSScreen {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens[0]
    }

    private func layout() {
        model.notch = NotchGeometry.detect(on: screen)
        panel.setFrame(frame(open: model.isOpen), display: true)
    }

    /// Closed, the window covers only the notch so it never steals clicks from the menu bar.
    private func frame(open: Bool) -> NSRect {
        let screenFrame = screen.frame
        let size = open
            ? CGSize(width: model.openSize.width + openMargin.width, height: model.openSize.height + openMargin.height)
            : CGSize(width: model.notch.width, height: model.notch.height)
        return NSRect(x: screenFrame.midX - size.width / 2,
                      y: screenFrame.maxY - size.height,
                      width: size.width,
                      height: size.height)
    }

    private func installMonitors() {
        // Clicks delivered to other apps mean the user clicked outside the panel.
        if let m = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: { [weak self] _ in
            Task { @MainActor in
                guard let self, self.model.isOpen, !self.panelContainsMouse else { return }
                self.close()
            }
        }) { monitors.append(m) }

        if let m = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] _ in
            Task { @MainActor in self?.trackMouse() }
        }) { monitors.append(m) }

        if let m = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { [weak self] event in
            Task { @MainActor in self?.trackMouse() }
            return event
        }) { monitors.append(m) }
    }

    /// Hit area of the visible panel (excluding the transparent shadow margin).
    private var panelContainsMouse: Bool {
        let frame = panel.frame
        let visible = NSRect(x: frame.midX - model.openSize.width / 2 - 14,
                             y: frame.maxY - model.openSize.height,
                             width: model.openSize.width + 28,
                             height: model.openSize.height)
        return visible.contains(NSEvent.mouseLocation)
    }

    private func trackMouse() {
        guard model.isOpen else { return }
        if panelContainsMouse {
            pendingClose?.cancel()
            pendingClose = nil
        } else if pendingClose == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.pendingClose = nil
                if !self.panelContainsMouse { self.close() }
            }
            pendingClose = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
        }
    }
}
