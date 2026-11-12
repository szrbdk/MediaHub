import AppKit
import SwiftUI

@main
enum MediaHubApp {
    static func main() {
        let defaults = UserDefaults.standard
        LegacyPreferencesMigration.migrate(store: defaults,
            legacyValues: defaults.persistentDomain(forName: LegacyPreferencesMigration.legacyDomain) ?? [:])
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
    private var addBlacklistItem: NSMenuItem?
    private var blacklistPanel: NSPanel?
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
            item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "MediaHub")
        }
        item.button?.setAccessibilityLabel("MediaHub")
        item.button?.toolTip = "MediaHub"
        statusItem = item
        buildMenu()
        controller.start()
    }

    private func buildMenu() {
        addBlacklistMenu.title = L("blacklist.add")
        let menu = NSMenu()
        menu.delegate = self
        menu.autoenablesItems = false
        let heading = NSMenuItem(title: "MediaHub", action: nil, keyEquivalent: "")
        heading.isEnabled = false
        menu.addItem(heading)
        menu.addItem(.separator())
        let notifications = NSMenuItem(title: L("menu.screen_display"), action: nil, keyEquivalent: "")
        let displayMenu = NSMenu(title: notifications.title)
        displayMenu.autoenablesItems = false
        notifications.submenu = displayMenu
        for mode in ScreenDisplayMode.allCases {
            let choice = NSMenuItem(title: L(mode.localizationKey), action: #selector(changeScreenDisplayMode(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = mode.rawValue
            choice.state = controller.screenDisplayMode == mode ? .on : .off
            localizedMenuItems.append((choice, mode.localizationKey))
            displayMenu.addItem(choice)
        }
        let touchBar = NSMenuItem(title: L("menu.touch_bar"), action: #selector(toggleTouchBar(_:)), keyEquivalent: "")
        touchBar.target = self
        touchBar.state = controller.touchBarEnabled ? .on : .off
        menu.addItem(touchBar)
        menu.addItem(.separator())
        menu.addItem(notifications)
        let autoSkip = NSMenuItem(title: L("menu.auto_skip"), action: #selector(toggleAutoSkip(_:)), keyEquivalent: "")
        autoSkip.target = self
        autoSkip.state = controller.autoSkipEnabled ? .on : .off
        autoSkip.toolTip = L("menu.auto_skip_hint")
        autoSkipItem = autoSkip
        let positionMenu = NSMenu(title: L("menu.notification_position"))
        positionMenu.autoenablesItems = false
        let positionItem = NSMenuItem(title: L("menu.notification_position"), action: nil, keyEquivalent: "")
        positionItem.submenu = positionMenu
        localizedMenuItems.append((positionItem, "menu.notification_position"))
        for position in NotificationPosition.allCases {
            let choice = NSMenuItem(title: L(position.localizationKey), action: #selector(changeNotificationPosition(_:)), keyEquivalent: "")
            choice.target = self
            choice.representedObject = position.rawValue
            choice.state = controller.notificationPosition == position ? .on : .off
            localizedMenuItems.append((choice, position.localizationKey))
            positionMenu.addItem(choice)
        }
        menu.addItem(positionItem)
        menu.addItem(.separator())
        menu.addItem(autoSkip)
        let addBlacklist = NSMenuItem(title: L("blacklist.add"), action: nil, keyEquivalent: "")
        addBlacklist.submenu = addBlacklistMenu
        addBlacklistItem = addBlacklist
        menu.addItem(addBlacklist)
        let manageBlacklist = NSMenuItem(title: L("menu.manage_blacklist"), action: #selector(showBlacklistPanel), keyEquivalent: "")
        manageBlacklist.target = self
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
        localizedMenuItems += [(notifications, "menu.screen_display"), (touchBar, "menu.touch_bar"), (autoSkip, "menu.auto_skip"),
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
                if item.action == #selector(changeNotificationPosition(_:)),
                   let value = item.representedObject as? String {
                    item.state = value == controller.notificationPosition.rawValue ? .on : .off
                }
                if item.action == #selector(changeScreenDisplayMode(_:)),
                   let value = item.representedObject as? String {
                    item.state = value == controller.screenDisplayMode.rawValue ? .on : .off
                }
                if item.submenu?.items.contains(where: { $0.action == #selector(changeNotificationPosition(_:)) }) == true {
                    item.isEnabled = controller.notificationsEnabled
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

    @objc private func changeNotificationPosition(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String,
              let position = NotificationPosition(rawValue: value) else { return }
        controller.setNotificationPosition(position)
        refreshMenuLanguage()
    }

    func menuWillOpen(_ menu: NSMenu) {
        controller.reloadBlacklist()
        refreshMenuLanguage()
    }

    private func refreshBlacklistMenus() {
        addBlacklistMenu.autoenablesItems = false
        addBlacklistMenu.removeAllItems()
        autoSkipItem?.state = controller.autoSkipEnabled ? .on : .off
        let state = controller.currentMediaState
        addBlacklistItem?.isEnabled = !state.isPodcast
        if let song = state.songBlacklistEntry {
            addBlacklistMenu.addItem(.sectionHeader(title: L("blacklist.song")))
            addEntry(song, title: state.title, to: addBlacklistMenu)
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
        if let panel = blacklistPanel {
            panel.title = L("menu.manage_blacklist")
            (panel.contentView as? NSHostingView<BlacklistManagerView>)?.rootView = blacklistManagerView()
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

    private func addEntry(_ entry: BlacklistEntry, title: String, to menu: NSMenu) {
        let item = NSMenuItem(title: String(title.prefix(80)),
                              action: #selector(addToBlacklist(_:)), keyEquivalent: "")
        item.target = self
        // Capture the displayed entry; a track change while the menu is open
        // must not silently replace what the user selected.
        item.representedObject = entry
        item.toolTip = title
        let exists = controller.blacklistDocument.contains(entry)
        item.state = exists ? .on : .off
        item.isEnabled = controller.canEditBlacklist && !exists
        menu.addItem(item)
    }

    @objc private func addToBlacklist(_ sender: NSMenuItem) {
        guard let entry = sender.representedObject as? BlacklistEntry else { return }
        controller.changeBlacklist(entry, adding: true)
        refreshBlacklistMenus()
    }

    @objc private func showBlacklistPanel() {
        controller.reloadBlacklist()
        if blacklistPanel == nil {
            let panel = NSPanel(contentRect: NSRect(origin: .zero, size: BlacklistManagerView.size),
                                styleMask: [.titled, .closable, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.appearance = NSAppearance(named: .darkAqua)
            panel.titlebarAppearsTransparent = true
            panel.backgroundColor = NSColor(white: 0.09, alpha: 1)
            panel.level = .floating
            panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .canJoinAllApplications]
            panel.contentView = NSHostingView(rootView: blacklistManagerView())
            blacklistPanel = panel
        }
        refreshBlacklistMenus()
        guard let panel = blacklistPanel else { return }
        let pointer = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? NSScreen.main {
            let area = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2,
                                         y: area.midY - panel.frame.height / 2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func blacklistManagerView() -> BlacklistManagerView {
        BlacklistManagerView(document: controller.blacklistDocument,
                             canRemove: controller.canEditBlacklist,
                             status: controller.blacklistStatus) { [weak self] entry in
            guard let self else { return }
            controller.changeBlacklist(entry, adding: false)
            refreshBlacklistMenus()
        }
    }

    @objc private func toggleAutoSkip(_ sender: NSMenuItem) {
        controller.setAutoSkipEnabled(!controller.autoSkipEnabled)
        sender.state = controller.autoSkipEnabled ? .on : .off
        refreshBlacklistMenus()
    }

    @objc private func changeScreenDisplayMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let mode = ScreenDisplayMode(rawValue: raw) else { return }
        controller.setScreenDisplayMode(mode)
        refreshMenuLanguage()
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
