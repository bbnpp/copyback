import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    /// 팝오버 열기/닫기 단축키: ⇧⌘V
    private static let hotKeyCode = kVK_ANSI_V
    private static let hotKeyModifiers = cmdKey | shiftKey

    private var history: ClipboardHistory!
    private var model: PanelModel!
    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var hotKey: HotKey?
    private var keyMonitor: Any?
    /// 팝오버를 열기 직전에 쓰던 앱. 닫을 때 포커스를 돌려준다.
    private var previousApp: NSRunningApplication?
    private var lastCloseDate = Date.distantPast

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isAnotherInstanceRunning() else {
            NSApp.terminate(nil)
            return
        }

        history = ClipboardHistory()
        model = PanelModel(history: history)
        model.onFinish = { [weak self] in self?.popover.performClose(nil) }

        setUpStatusItem()
        setUpPopover()
        history.startMonitoring()

        hotKey = HotKey(keyCode: Self.hotKeyCode, modifiers: Self.hotKeyModifiers) { [weak self] in
            self?.togglePopover()
        }
        if hotKey == nil {
            NSLog("Copyback: 전역 단축키(⇧⌘V) 등록 실패")
        }

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown else { return event }
            return self.handleKeyDown(event) ? nil : event
        }
    }

    private func isAnotherInstanceRunning() -> Bool {
        guard let bundleID = Bundle.main.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .contains { $0 != NSRunningApplication.current }
    }

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "클립보드 기록")
            button.target = self
            button.action = #selector(statusItemClicked(_:))
        }
        statusItem = item
    }

    private func setUpPopover() {
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentSize = NSSize(width: PanelLayout.width, height: PanelLayout.height)
        popover.contentViewController = NSHostingController(rootView: HistoryView(model: model, history: history))
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        // 열린 팝오버의 아이콘을 누르면 transient 닫힘이 먼저 일어나므로 곧바로 다시 열지 않는다
        guard Date().timeIntervalSince(lastCloseDate) > 0.25 else { return }
        togglePopover()
    }

    private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover()
        }
    }

    private func showPopover() {
        guard let button = statusItem?.button else { return }
        let frontmost = NSWorkspace.shared.frontmostApplication
        if frontmost != NSRunningApplication.current {
            previousApp = frontmost
        }
        model.prepareForDisplay()
        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        model.focusSearchField()
    }

    func popoverDidClose(_ notification: Notification) {
        lastCloseDate = Date()
        // 다른 앱을 클릭해서 닫힌 경우엔 그 앱이 이미 활성화돼 있으므로 건드리지 않는다
        if NSApp.isActive, let previousApp, !previousApp.isTerminated {
            previousApp.activate(from: .current, options: [])
        }
    }

    /// 팝오버가 열려 있을 때의 키보드 조작. 처리했으면 true.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        // 한글 등 입력기 조합 중에는 입력기가 키를 먼저 처리하게 둔다
        if let editor = popover.contentViewController?.view.window?.firstResponder as? NSTextView,
           editor.hasMarkedText() {
            return false
        }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])

        switch Int(event.keyCode) {
        case kVK_DownArrow:
            model.moveSelection(by: 1)
        case kVK_UpArrow:
            model.moveSelection(by: -1)
        case kVK_Return, kVK_ANSI_KeypadEnter:
            model.copySelected()
        case kVK_Escape:
            if model.query.isEmpty {
                popover.performClose(nil)
            } else {
                model.query = ""
            }
        case kVK_Delete where modifiers == .command:
            model.deleteSelected()
        default:
            // ⌘1~⌘9: 목록의 n번째 항목 복사
            guard modifiers == .command,
                  let number = event.charactersIgnoringModifiers.flatMap({ Int($0) }),
                  (1...9).contains(number) else { return false }
            model.copy(at: number - 1)
        }
        return true
    }
}
