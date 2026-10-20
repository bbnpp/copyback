import AppKit
import ServiceManagement

/// 팝오버 화면 상태(검색어, 키보드 선택)와 동작
@MainActor
final class PanelModel: ObservableObject {
    @Published var query = "" {
        didSet { selectedID = visibleItems.first?.id }
    }
    @Published var selectedID: ClipItem.ID?
    /// 키보드로 선택을 옮겼을 때만 스크롤하기 위한 값 (마우스 호버로는 스크롤하지 않음)
    @Published private(set) var scrollTarget: ClipItem.ID?
    /// 값이 바뀔 때마다 검색창에 포커스를 준다
    @Published private(set) var focusRequest = 0
    @Published private(set) var launchAtLogin = false

    let history: ClipboardHistory
    /// 항목을 복사한 뒤 호출된다 (팝오버 닫기)
    var onFinish: (() -> Void)?

    private let thumbnails = NSCache<NSString, NSImage>()
    private var icons: [String: NSImage] = [:]

    init(history: ClipboardHistory) {
        self.history = history
    }

    var visibleItems: [ClipItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return history.items }
        return history.items.filter {
            $0.text.localizedCaseInsensitiveContains(query)
                || ($0.appName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    var selectedItem: ClipItem? {
        selectedItem(in: visibleItems)
    }

    /// 선택된 항목. 선택이 목록에 없으면 첫 항목.
    func selectedItem(in items: [ClipItem]) -> ClipItem? {
        items.first { $0.id == selectedID } ?? items.first
    }

    func prepareForDisplay() {
        query = ""
        selectedID = history.items.first?.id
        scrollTarget = selectedID
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func focusSearchField() {
        focusRequest += 1
    }

    func moveSelection(by offset: Int) {
        let items = visibleItems
        guard !items.isEmpty else { return }
        let currentID = selectedItem(in: items)?.id
        let current = items.firstIndex { $0.id == currentID } ?? 0
        let next = min(max(current + offset, 0), items.count - 1)
        selectedID = items[next].id
        scrollTarget = items[next].id
    }

    func copy(_ item: ClipItem) {
        if history.copyToPasteboard(item) {
            onFinish?()
        } else {
            NSSound.beep()
        }
    }

    func copySelected() {
        if let item = selectedItem { copy(item) }
    }

    /// ⌘1~⌘9: 현재 보이는 목록의 index번째 항목
    func copy(at index: Int) {
        let items = visibleItems
        guard items.indices.contains(index) else { return }
        copy(items[index])
    }

    func delete(_ item: ClipItem) {
        let items = visibleItems
        if item.id == selectedItem(in: items)?.id, let index = items.firstIndex(of: item) {
            // 지운 자리의 다음 항목(없으면 이전 항목)을 선택
            let neighbor = items.indices.contains(index + 1) ? items[index + 1] : (index > 0 ? items[index - 1] : nil)
            selectedID = neighbor?.id
        }
        history.remove(item)
    }

    func deleteSelected() {
        if let item = selectedItem { delete(item) }
    }

    func clearAll() {
        history.removeAll()
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        let service = SMAppService.mainApp
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            NSLog("Copyback: 로그인 항목 설정 실패: \(error)")
        }
        if service.status == .requiresApproval {
            SMAppService.openSystemSettingsLoginItems()
        }
        launchAtLogin = service.status == .enabled
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func thumbnail(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        guard let image = NSImage(contentsOf: history.storage.thumbnailURL(for: item.id)) else { return nil }
        thumbnails.setObject(image, forKey: key)
        return image
    }

    func appIcon(for item: ClipItem) -> NSImage? {
        guard let bundleID = item.appBundleID else { return nil }
        if let cached = icons[bundleID] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icons[bundleID] = icon
        return icon
    }

    func fileIcon(path: String) -> NSImage {
        let key = "file:" + path
        if let cached = icons[key] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: path)
        icons[key] = icon
        return icon
    }
}
