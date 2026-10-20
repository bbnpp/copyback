import Foundation

/// 디스크 저장소. 기본 위치: ~/Library/Application Support/Copyback
///   history.json      목록 (ClipItem 배열)
///   blobs/<id>.plist  클립보드 원본 데이터
///   thumbs/<id>.png   이미지 미리보기
/// 클립보드에는 민감한 내용이 섞일 수 있어 폴더 권한은 0700, Time Machine 백업에서는 제외한다.
struct HistoryStorage {
    let directory: URL

    static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Copyback", isDirectory: true)
    }

    init(directory: URL = HistoryStorage.defaultDirectory) {
        self.directory = directory
        createDirectories()
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var url = directory
        try? url.setResourceValues(values)
    }

    private var indexURL: URL { directory.appendingPathComponent("history.json") }
    private var blobsDirectory: URL { directory.appendingPathComponent("blobs", isDirectory: true) }
    private var thumbsDirectory: URL { directory.appendingPathComponent("thumbs", isDirectory: true) }
    private static let corruptBackupPrefix = "history.corrupt-"

    private func createDirectories() {
        for dir in [directory, blobsDirectory, thumbsDirectory] {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                     attributes: [.posixPermissions: 0o700])
        }
    }

    func blobURL(for id: UUID) -> URL {
        blobsDirectory.appendingPathComponent("\(id.uuidString).plist")
    }

    func thumbnailURL(for id: UUID) -> URL {
        thumbsDirectory.appendingPathComponent("\(id.uuidString).png")
    }

    /// 저장된 목록. 읽을 수 없으면 nil (깨진 파일은 옆으로 옮겨 둔다).
    func loadIndex() -> [ClipItem]? {
        guard FileManager.default.fileExists(atPath: indexURL.path) else { return [] }
        guard let data = try? Data(contentsOf: indexURL) else {
            NSLog("Copyback: history.json을 읽을 수 없음")
            return nil
        }
        do {
            return try JSONDecoder().decode([ClipItem].self, from: data)
        } catch {
            NSLog("Copyback: history.json 읽기 실패, 백업 후 새로 시작: \(error)")
            let backup = directory.appendingPathComponent("\(Self.corruptBackupPrefix)\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: indexURL, to: backup)
            return nil
        }
    }

    func saveIndex(_ items: [ClipItem]) {
        do {
            try JSONEncoder().encode(items).write(to: indexURL, options: .atomic)
        } catch {
            NSLog("Copyback: history.json 저장 실패: \(error)")
        }
    }

    func saveBlob(_ items: [[PasteboardEntry]], for id: UUID) throws {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        try encoder.encode(items).write(to: blobURL(for: id), options: .atomic)
    }

    func loadBlob(for id: UUID) -> [[PasteboardEntry]]? {
        guard let data = try? Data(contentsOf: blobURL(for: id)) else { return nil }
        return try? PropertyListDecoder().decode([[PasteboardEntry]].self, from: data)
    }

    func saveThumbnail(_ png: Data, for id: UUID) {
        try? png.write(to: thumbnailURL(for: id), options: .atomic)
    }

    func deleteFiles(for id: UUID) {
        try? FileManager.default.removeItem(at: blobURL(for: id))
        try? FileManager.default.removeItem(at: thumbnailURL(for: id))
    }

    /// 목록에 없는 데이터 파일을 지운다 (저장 도중 비정상 종료로 남은 파일 정리)
    func deleteFiles(notIn ids: Set<UUID>) {
        for dir in [blobsDirectory, thumbsDirectory] {
            let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for file in files {
                guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                      !ids.contains(id) else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    /// 목록에 없는 파일, 깨진 목록 백업까지 포함해 기록 데이터를 전부 지운다
    func deleteAll() {
        try? FileManager.default.removeItem(at: blobsDirectory)
        try? FileManager.default.removeItem(at: thumbsDirectory)
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in files where file.lastPathComponent.hasPrefix(Self.corruptBackupPrefix) {
            try? FileManager.default.removeItem(at: file)
        }
        createDirectories()
        saveIndex([])
    }
}
