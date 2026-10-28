import AppKit

@main
enum MediaBarApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let controller = MediaController()
    private var terminating = false
    private let addBlacklistMenu = NSMenu(title: "Karalisteye ekle")
    private let manageBlacklistMenu = NSMenu(title: "Karalisteyi yönet")
    private var autoSkipItem: NSMenuItem?
    private var blacklistStatusItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let icon = NSImage(named: "MenuBarIcon") {
            icon.isTemplate = true
            icon.size = NSSize(width: 18, height: 18)
            item.button?.image = icon
        } else {
            item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MediaBar")
        }
        item.button?.setAccessibilityLabel("MediaBar")
        item.button?.toolTip = "MediaBar"
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: "MediaBar", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        let notifications = NSMenuItem(title: "Bildirimler", action: #selector(toggleNotifications(_:)), keyEquivalent: "")
        notifications.target = self
        notifications.state = controller.notificationsEnabled ? .on : .off
        menu.addItem(notifications)
        let touchBar = NSMenuItem(title: "Touch Bar", action: #selector(toggleTouchBar(_:)), keyEquivalent: "")
        touchBar.target = self
        touchBar.state = controller.touchBarEnabled ? .on : .off
        menu.addItem(touchBar)
        let autoSkip = NSMenuItem(title: "Otomatik atlama", action: #selector(toggleAutoSkip(_:)), keyEquivalent: "")
        autoSkip.target = self
        autoSkip.state = controller.autoSkipEnabled ? .on : .off
        autoSkip.toolTip = "Yalnızca yeni başlayan parçalar için karalisteyi uygular. Art arda en fazla 10 parça atlar; kapatıp açmak sınırı sıfırlar."
        autoSkipItem = autoSkip
        menu.addItem(autoSkip)
        menu.addItem(.separator())
        let addBlacklist = NSMenuItem(title: "Karalisteye ekle", action: nil, keyEquivalent: "")
        addBlacklist.submenu = addBlacklistMenu
        menu.addItem(addBlacklist)
        let manageBlacklist = NSMenuItem(title: "Karalisteyi yönet", action: nil, keyEquivalent: "")
        manageBlacklist.submenu = manageBlacklistMenu
        menu.addItem(manageBlacklist)
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.isHidden = true
        blacklistStatusItem = status
        menu.addItem(status)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        controller.start()
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.reloadBlacklist()
        refreshBlacklistMenus()
    }

    private func refreshBlacklistMenus() {
        addBlacklistMenu.autoenablesItems = false
        manageBlacklistMenu.autoenablesItems = false
        addBlacklistMenu.removeAllItems()
        manageBlacklistMenu.removeAllItems()
        autoSkipItem?.state = controller.autoSkipEnabled ? .on : .off
        let state = controller.currentMediaState
        let document = controller.blacklistDocument
        if state.hasMedia && !blacklistKey(state.artistText).isEmpty {
            addBlacklistMenu.addItem(.sectionHeader(title: "Şarkı"))
            addEntry(.song(BlacklistedSong(title: state.title, artistText: state.artistText)),
                     title: state.title, to: addBlacklistMenu)
            addBlacklistMenu.addItem(.separator())
            addBlacklistMenu.addItem(.sectionHeader(title: "Sanatçılar"))
            if !state.artistNames.isEmpty {
                for name in state.artistNames {
                    addEntry(.artist(BlacklistedArtist(name: name, match: .individual)), title: name, to: addBlacklistMenu)
                }
            } else {
                addEntry(.artist(BlacklistedArtist(name: state.artistText, match: .fullText)),
                         title: state.artistText, to: addBlacklistMenu)
            }
        } else {
            addBlacklistMenu.addItem(disabledItem("Şarkı ve sanatçı bilgisi bekleniyor"))
        }
        if document.artists.isEmpty && document.songs.isEmpty {
            manageBlacklistMenu.addItem(disabledItem("Karaliste boş"))
        } else {
            if !document.artists.isEmpty {
                manageBlacklistMenu.addItem(.sectionHeader(title: "Sanatçılar"))
                for artist in document.artists {
                    addEntry(.artist(artist), title: artist.name, to: manageBlacklistMenu, removing: true)
                }
            }
            if !document.songs.isEmpty {
                if !document.artists.isEmpty { manageBlacklistMenu.addItem(.separator()) }
                manageBlacklistMenu.addItem(.sectionHeader(title: "Şarkılar"))
                for song in document.songs {
                    addEntry(.song(song), title: "\(song.title) — \(song.artistText)", to: manageBlacklistMenu, removing: true)
                }
            }
        }
        let status = controller.blacklistStatus
        blacklistStatusItem?.isHidden = status == nil
        blacklistStatusItem?.title = status.map { String($0.prefix(75)) } ?? ""
        blacklistStatusItem?.toolTip = status
    }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func addEntry(_ entry: BlacklistEntry, title: String, to menu: NSMenu, removing: Bool = false) {
        let item = NSMenuItem(title: String(title.prefix(80)),
                              action: removing ? #selector(removeFromBlacklist(_:)) : #selector(addToBlacklist(_:)), keyEquivalent: "")
        item.target = self
        // Capture the displayed entry; a track change while the menu is open
        // must not silently replace what the user selected.
        item.representedObject = entry
        item.toolTip = removing ? "Karalisteden kaldır: \(title)" : title
        let exists = controller.blacklistDocument.contains(entry)
        item.state = !removing && exists ? .on : .off
        item.isEnabled = controller.canEditBlacklist && (removing || !exists)
        menu.addItem(item)
    }

    @objc private func addToBlacklist(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? BlacklistEntry else { return }
        controller.changeBlacklist(entry, adding: true)
        refreshBlacklistMenus()
    }

    @objc private func removeFromBlacklist(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? BlacklistEntry else { return }
        controller.changeBlacklist(entry, adding: false)
        refreshBlacklistMenus()
    }

    @objc private func toggleAutoSkip(_ sender: NSMenuItem) {
        controller.setAutoSkipEnabled(!controller.autoSkipEnabled)
        sender.state = controller.autoSkipEnabled ? .on : .off
        refreshBlacklistMenus()
    }

    @objc private func toggleNotifications(_ sender: NSMenuItem) {
        controller.setNotificationsEnabled(!controller.notificationsEnabled)
        sender.state = controller.notificationsEnabled ? .on : .off
    }

    @objc private func toggleTouchBar(_ sender: NSMenuItem) {
        controller.setTouchBarEnabled(!controller.touchBarEnabled)
        sender.state = controller.touchBarEnabled ? .on : .off
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !terminating else { return .terminateLater }
        terminating = true
        controller.stop { DispatchQueue.main.async { sender.reply(toApplicationShouldTerminate: true) } }
        return .terminateLater
    }
}
