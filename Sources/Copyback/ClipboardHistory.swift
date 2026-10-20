import AppKit

/// 클립보드를 감시해 기록을 쌓고, 기록된 항목을 다시 클립보드에 복사한다.
@MainActor
final class ClipboardHistory: ObservableObject {
    /// 표시 타입 없이 비밀번호를 복사할 수 있는 시스템 앱. 이 앱에서 복사한 내용은 기록하지 않는다.
    static let ignoredAppBundleIDs: Set<String> = [
        "com.apple.Passwords",
        "com.apple.keychainaccess",
    ]

    @Published private(set) var items: [ClipItem]

    let storage: HistoryStorage
    private let pasteboard: NSPasteboard
    private let maxItems: Int
    private var lastChangeCount: Int
    private var timer: Timer?

    init(pasteboard: NSPasteboard = .general, storage: HistoryStorage = HistoryStorage(), maxItems: Int = 300) {
        self.pasteboard = pasteboard
        self.storage = storage
        self.maxItems = maxItems
        self.lastChangeCount = pasteboard.changeCount
        if let saved = storage.loadIndex() {
            self.items = saved
            storage.deleteFiles(notIn: Set(saved.map(\.id)))
        } else {
            self.items = []
        }
    }

    /// macOS에는 클립보드 변경 알림이 없어서 changeCount를 주기적으로 확인한다.
    func startMonitoring(interval: TimeInterval = 0.5) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkPasteboard() }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func checkPasteboard() {
        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount
        let app = NSWorkspace.shared.frontmostApplication
        if let bundleID = app?.bundleIdentifier, Self.ignoredAppBundleIDs.contains(bundleID) { return }
        guard let snapshot = PasteboardCodec.snapshot(of: pasteboard) else { return }
        add(snapshot, appName: app?.localizedName, appBundleID: app?.bundleIdentifier)
    }

    private func add(_ snapshot: PasteboardSnapshot, appName: String?, appBundleID: String?) {
        let item = ClipItem(id: UUID(), kind: snapshot.kind, date: Date(), text: snapshot.text,
                            contentHash: snapshot.contentHash, appName: appName, appBundleID: appBundleID)
        do {
            try storage.saveBlob(snapshot.items, for: item.id)
        } catch {
            NSLog("Copyback: 클립보드 데이터 저장 실패: \(error)")
            return
        }
        if let thumbnail = snapshot.thumbnailPNG {
            storage.saveThumbnail(thumbnail, for: item.id)
        }

        // 같은 내용을 다시 복사하면 기존 항목을 지우고 맨 위에 새로 올린다
        var updated = items
        for duplicate in updated where duplicate.contentHash == item.contentHash {
            storage.deleteFiles(for: duplicate.id)
        }
        updated.removeAll { $0.contentHash == item.contentHash }
        updated.insert(item, at: 0)
        while updated.count > maxItems {
            storage.deleteFiles(for: updated.removeLast().id)
        }
        items = updated
        storage.saveIndex(items)
    }

    /// 기록된 항목을 클립보드에 다시 복사하고 목록 맨 위로 올린다.
    @discardableResult
    func copyToPasteboard(_ item: ClipItem) -> Bool {
        guard let data = storage.loadBlob(for: item.id), PasteboardCodec.write(data, to: pasteboard) else {
            return false
        }
        lastChangeCount = pasteboard.changeCount  // 직접 쓴 변경은 새 기록으로 잡지 않는다

        if let index = items.firstIndex(where: { $0.id == item.id }) {
            var updated = items
            var moved = updated.remove(at: index)
            moved.date = Date()
            updated.insert(moved, at: 0)
            items = updated
            storage.saveIndex(items)
        }
        return true
    }

    func remove(_ item: ClipItem) {
        storage.deleteFiles(for: item.id)
        items.removeAll { $0.id == item.id }
        storage.saveIndex(items)
    }

    func removeAll() {
        storage.deleteAll()
        items = []
    }
}
