import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = UsageStore()
    private var notch: NotchController?
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let notch = NotchController(store: store)
        self.notch = notch
        statusItem = StatusItemController(store: store, notch: notch)

        LoginItem.enableOnFirstLaunch()
        store.start()
    }
}

enum AppAssets {
    static let logo: NSImage? = {
        guard let url = Bundle.main.url(forResource: "logo", withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }()
}
