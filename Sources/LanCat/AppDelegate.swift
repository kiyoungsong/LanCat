import AppKit
import Combine
import ServiceManagement
import SwiftUI
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = NetworkMonitor()
    let store = ThemeStore.shared
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var cancellables = Set<AnyCancellable>()

    // 상태별 프레임과 각 프레임 표시 시간(초)
    private var sequence: [(NSImage, TimeInterval)] = []
    private var frameIndex = 0
    private var animTimer: Timer?
    private let launchDate = Date()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageOnly
        }

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.contentViewController = NSHostingController(rootView: PopoverView(
            monitor: monitor,
            store: store,
            openSettings: { [weak self] in self?.openSettings() }
        ))

        monitor.$state
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.applyAnimation(for: $0) }
            .store(in: &cancellables)

        // 설정에서 이미지를 바꾸면 메뉴바 아이콘도 바로 바뀌게
        store.$revision
            .dropFirst()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.applyAnimation(for: self.monitor.state)
            }
            .store(in: &cancellables)

        monitor.onStateChange = { [weak self] old, new in
            self?.notify(from: old, to: new)
        }

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        monitor.start()
        UpdateChecker.shared.start()
        applyAnimation(for: monitor.state)
    }

    // MARK: - 메뉴바 애니메이션

    private func applyAnimation(for state: LinkState) {
        let frames = store.frames(for: ThemeSlot.icon(for: state))
        sequence = Array(zip(frames.images, frames.durations))
        frameIndex = 0
        let tip: String
        switch state {
        case .connected: tip = L("tooltip.connected")
        case .noInternet: tip = L("tooltip.noInternet")
        case .unplugged: tip = L("tooltip.unplugged")
        }
        statusItem.button?.toolTip = tip
        showFrame()
    }

    private func showFrame() {
        animTimer?.invalidate()
        guard !sequence.isEmpty else { return }
        let (img, dur) = sequence[frameIndex % sequence.count]
        statusItem.button?.image = img
        animTimer = Timer.scheduledTimer(withTimeInterval: dur, repeats: false) { [weak self] _ in
            guard let self else { return }
            self.frameIndex += 1
            self.showFrame()
        }
        RunLoop.main.add(animTimer!, forMode: .common)
    }

    // MARK: - 클릭

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            monitor.refreshNow()
            monitor.popoverOpenTick += 1
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: L("menu.settings"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())

        // 테스트용 상태 미리보기
        let simItem = NSMenuItem(title: L("menu.preview"), action: nil, keyEquivalent: "")
        let sub = NSMenu()
        let options: [(String, LinkState?)] = [
            (L("menu.preview.real"), nil),
            (L("state.connected"), .connected),
            (L("state.noInternet"), .noInternet),
            (L("state.unplugged"), .unplugged),
        ]
        for (i, (title, value)) in options.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(simulate(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = monitor.simulatedState == value ? .on : .off
            sub.addItem(item)
            if i == 0 { sub.addItem(.separator()) }
        }
        simItem.submenu = sub
        menu.addItem(simItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: L("menu.quit"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc func openSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 660, height: 640),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = L("settings.windowTitle")
            window.isReleasedWhenClosed = false
            window.contentViewController = NSHostingController(rootView: SettingsView(store: store))
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func simulate(_ sender: NSMenuItem) {
        let states: [LinkState?] = [nil, .connected, .noInternet, .unplugged]
        monitor.simulatedState = states[sender.tag]
    }

    // MARK: - 알림

    private func notify(from old: LinkState, to new: LinkState) {
        // 앱 켜자마자 상태가 잡히는 건 알리지 않음
        guard Date().timeIntervalSince(launchDate) > 8 else { return }
        let content = UNMutableNotificationContent()
        switch new {
        case .unplugged:
            content.title = L("notif.unplugged.title")
            content.body = L("notif.unplugged.body")
        case .noInternet:
            content.title = L("notif.noInternet.title")
            content.body = L("notif.noInternet.body")
        case .connected:
            guard old != .connected else { return }
            content.title = L("notif.connected.title")
            content.body = L("notif.connected.body")
        }
        let req = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }
}
