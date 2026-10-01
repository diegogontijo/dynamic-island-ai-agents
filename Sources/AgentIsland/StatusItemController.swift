import AppKit
import ServiceManagement

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let store: UsageStore
    private let notch: NotchController
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

    init(store: UsageStore, notch: NotchController) {
        self.store = store
        self.notch = notch
        super.init()

        if let button = item.button {
            if let logo = AppAssets.logo?.copy() as? NSImage {
                logo.size = NSSize(width: 18, height: 18)
                button.image = logo
            } else {
                button.image = NSImage(systemSymbolName: "gauge.with.dots.needle.67percent",
                                       accessibilityDescription: "Agent Island")
            }
        }
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        menu.addItem(summaryItem("Claude Code", store.claude))
        menu.addItem(summaryItem("Codex", store.codex))
        menu.addItem(.separator())

        menu.addItem(action(notch.isOpen ? "Fechar painel" : "Abrir painel", #selector(togglePanel)))
        menu.addItem(action("Atualizar agora", #selector(refresh), key: "r"))
        menu.addItem(.separator())

        let login = action("Abrir ao iniciar sessão", #selector(toggleLogin))
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(action("Sair", #selector(quit), key: "q"))
    }

    private func summaryItem(_ name: String, _ snapshot: ProviderSnapshot) -> NSMenuItem {
        let text: String
        if let session = snapshot.usage?.session {
            text = "\(name): \(Int(session.remainingPercent.rounded()))% restante · \(Format.sessionReset(session.resetsAt, now: Date()))"
        } else if let error = snapshot.error {
            text = "\(name): \(error)"
        } else {
            text = "\(name): carregando…"
        }
        let item = NSMenuItem(title: text, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func action(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func togglePanel() { notch.toggle() }
    @objc private func refresh() { store.refresh() }
    @objc private func toggleLogin() { LoginItem.setEnabled(!LoginItem.isEnabled) }
    @objc private func quit() { NSApp.terminate(nil) }
}

enum LoginItem {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }

    static func setEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("AgentIsland: login item update failed: \(error)")
        }
    }

    /// The app should start at login by default; after that the menu toggle is respected.
    static func enableOnFirstLaunch() {
        let key = "loginItemConfigured"
        guard Bundle.main.bundleURL.pathExtension == "app",
              !UserDefaults.standard.bool(forKey: key) else { return }
        setEnabled(true)
        UserDefaults.standard.set(true, forKey: key)
    }
}
