import AppKit
import SwiftUI
import Combine
import AQICore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    let store = AQIStore(key: { Credentials.activeKey })
    private var statusItem: NSStatusItem!
    private var window: NSWindow?
    private var timer: Timer?
    private var observer: AnyCancellable?
    private var wakeObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        Credentials.importExistingPluginKey()
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "AQIBar"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu
        observer = store.objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateStatus() }
        }
        updateStatus()
        store.refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.store.refresh() } }
        if !UserDefaults.standard.bool(forKey: "hasLaunched") {
            UserDefaults.standard.set(true, forKey: "hasLaunched")
            showSettings()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        store.cancel()
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private func updateStatus() {
        guard let button = statusItem.button else { return }
        let text: String
        if let reading = store.reading {
            text = "AQI \(reading.value)\(store.isStale ? " ·" : "")"
            button.toolTip = "\(reading.place)\nUS AQI \(reading.value) — \(reading.band.title)\(store.isStale ? "\nLast known reading; open for details" : "")"
        } else {
            text = store.isRefreshing ? "AQI …" : "AQI --"
            button.toolTip = store.errorMessage ?? "Choose your location in AQI Bar Settings"
        }
        button.image = StatusRenderer.image(text: text, band: store.reading?.band,
                                            height: max(18, button.bounds.height))
        button.imagePosition = .imageOnly
        button.setAccessibilityLabel(button.toolTip ?? text)
        button.setAccessibilityIdentifier("aqi-status-item")
    }

    func menuWillOpen(_ menu: NSMenu) { updateStatus(); rebuildMenu(menu) }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        if let reading = store.reading {
            info(reading.place, in: menu)
            let quality = info("US AQI \(reading.value) — \(reading.band.title)", in: menu)
            quality.attributedTitle = NSAttributedString(string: quality.title, attributes: [.foregroundColor: reading.band.nsColor])
            if let date = reading.observedAt { info("Measured \(date.formatted(date: .abbreviated, time: .shortened))", in: menu) }
            info("Checked \(reading.fetchedAt.formatted(date: .omitted, time: .shortened))", in: menu)
            if store.isStale { info("Last known reading · awaiting fresh data", in: menu) }
        } else { info(store.isRefreshing ? "Checking air quality…" : "No reading available", in: menu) }
        if let error = store.errorMessage { info(error, in: menu) }
        menu.addItem(.separator())
        let refresh = action(store.isRefreshing ? "Refreshing…" : "Refresh Now", #selector(refreshNow), in: menu)
        refresh.isEnabled = !store.isRefreshing
        action("Location & Settings…", #selector(showSettings), in: menu, key: ",")
        action("IQAir ↗", #selector(openIQAir), in: menu)
        menu.addItem(.separator())
        action("Quit AQI Bar", #selector(quit), in: menu, key: "q")
    }

    @discardableResult private func info(_ title: String, in menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
        return item
    }

    @discardableResult private func action(_ title: String, _ selector: Selector, in menu: NSMenu, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
        return item
    }

    @objc func showSettings() {
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(store: store))
            let window = NSWindow(contentViewController: controller)
            window.title = "AQI Bar Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    @objc private func refreshNow() { store.refresh() }
    @objc private func openIQAir() { NSWorkspace.shared.open(URL(string: "https://www.iqair.com/")!) }
    @objc private func quit() { NSApp.terminate(nil) }
}
