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
    private let addBlacklistMenu = NSMenu(title: L("blacklist.add"))
    private let manageBlacklistMenu = NSMenu(title: L("menu.manage_blacklist"))
    private var autoSkipItem: NSMenuItem?
    private var blacklistStatusItem: NSMenuItem?
    private var localizedMenuItems: [(item: NSMenuItem, key: String)] = []

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
        statusItem = item
        buildMenu()
        controller.start()
    }

    private func buildMenu() {
        addBlacklistMenu.title = L("blacklist.add")
        manageBlacklistMenu.title = L("menu.manage_blacklist")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: "MediaBar", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        let notifications = NSMenuItem(title: L("menu.notifications"), action: #selector(toggleNotifications(_:)), keyEquivalent: "")
        notifications.target = self
        notifications.state = controller.notificationsEnabled ? .on : .off
        let touchBar = NSMenuItem(title: L("menu.touch_bar"), action: #selector(toggleTouchBar(_:)), keyEquivalent: "")
        touchBar.target = self
        touchBar.state = controller.touchBarEnabled ? .on : .off
        menu.addItem(touchBar)
        menu.addItem(notifications)
        let autoSkip = NSMenuItem(title: L("menu.auto_skip"), action: #selector(toggleAutoSkip(_:)), keyEquivalent: "")
        autoSkip.target = self
        autoSkip.state = controller.autoSkipEnabled ? .on : .off
        autoSkip.toolTip = L("menu.auto_skip_hint")
        autoSkipItem = autoSkip
        menu.addItem(autoSkip)
        menu.addItem(.separator())
        let addBlacklist = NSMenuItem(title: L("blacklist.add"), action: nil, keyEquivalent: "")
        addBlacklist.submenu = addBlacklistMenu
        menu.addItem(addBlacklist)
        let manageBlacklist = NSMenuItem(title: L("menu.manage_blacklist"), action: nil, keyEquivalent: "")
        manageBlacklist.submenu = manageBlacklistMenu
        menu.addItem(manageBlacklist)
        let status = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        status.isEnabled = false
        status.isHidden = true
        blacklistStatusItem = status
        menu.addItem(status)
        menu.addItem(.separator())
        let languageMenu = NSMenu(title: L("menu.language"))
        languageMenu.autoenablesItems = false
        let languageItem = NSMenuItem(title: L("menu.language"), action: nil, keyEquivalent: "")
        languageItem.submenu = languageMenu
        for language in AppLanguage.allCases {
            let title = L(language == .tr ? "language.turkish" : "language.english")
            let choice = NSMenuItem(title: title, action: #selector(changeLanguage(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = language.rawValue
            localizedMenuItems.append((choice, language == .tr ? "language.turkish" : "language.english"))
            choice.state = Localization.shared.language == language ? .on : .off
            languageMenu.addItem(choice)
        }
        menu.addItem(languageItem)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        localizedMenuItems += [(notifications, "menu.notifications"), (touchBar, "menu.touch_bar"), (autoSkip, "menu.auto_skip"),
                            (addBlacklist, "blacklist.add"), (manageBlacklist, "menu.manage_blacklist"),
                            (languageItem, "menu.language"), (quit, "menu.quit")]
        statusItem?.menu = menu
        refreshBlacklistMenus()
    }

    private func refreshMenuLanguage() {
        guard let menu = statusItem?.menu else { return }
        // AppKit may derive an item's identifier from its action selector.
        // Only explicitly registered translation keys should change a title.
        for (item, key) in localizedMenuItems { item.title = L(key) }
        // Keep the attached menu and submenus alive. A submenu can have only one
        // parent item; rebuilding with the existing blacklist submenus tries to
        // attach them to a second parent while the original menu is still active.
        func refresh(_ menu: NSMenu) {
            for item in menu.items {
                if item.action == #selector(changeLanguage(_:)),
                   let value = item.representedObject as? String {
                    item.state = value == Localization.shared.language.rawValue ? .on : .off
                }
                if let submenu = item.submenu {
                    submenu.title = item.title
                    refresh(submenu)
                }
            }
        }
        refresh(menu)
        autoSkipItem?.toolTip = L("menu.auto_skip_hint")
        refreshBlacklistMenus()
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String, let language = AppLanguage(rawValue: value) else { return }
        Localization.shared.language = language
        controller.refreshLanguage()
        refreshMenuLanguage()
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.reloadBlacklist()
        refreshMenuLanguage()
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
            addBlacklistMenu.addItem(.sectionHeader(title: L("blacklist.song")))
            addEntry(.song(BlacklistedSong(title: state.title, artistText: state.artistText)),
                     title: state.title, to: addBlacklistMenu)
            addBlacklistMenu.addItem(.separator())
            addBlacklistMenu.addItem(.sectionHeader(title: L("blacklist.artists")))
            if !state.artistNames.isEmpty {
                for name in state.artistNames {
                    addEntry(.artist(BlacklistedArtist(name: name, match: .individual)), title: name, to: addBlacklistMenu)
                }
            } else {
                addEntry(.artist(BlacklistedArtist(name: state.artistText, match: .fullText)),
                         title: state.artistText, to: addBlacklistMenu)
            }
        } else {
            addBlacklistMenu.addItem(disabledItem(L("blacklist.waiting_for_metadata")))
        }
        if document.artists.isEmpty && document.songs.isEmpty {
            manageBlacklistMenu.addItem(disabledItem(L("blacklist.empty")))
        } else {
            if !document.artists.isEmpty {
                manageBlacklistMenu.addItem(.sectionHeader(title: L("blacklist.artists")))
                for artist in document.artists {
                    addEntry(.artist(artist), title: artist.name, to: manageBlacklistMenu, removing: true)
                }
            }
            if !document.songs.isEmpty {
                if !document.artists.isEmpty { manageBlacklistMenu.addItem(.separator()) }
                manageBlacklistMenu.addItem(.sectionHeader(title: L("blacklist.songs")))
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
        item.toolTip = removing ? "\(L("blacklist.remove")): \(title)" : title
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
