// `make test`로 실행. 사용자의 실제 클립보드 대신 임시 pasteboard와 임시 폴더를 쓴다.
import AppKit

var failures = 0

func expect(_ condition: Bool, _ message: String, line: Int = #line) {
    if condition {
        print("  ok   \(message)")
    } else {
        failures += 1
        print("  FAIL \(message) (Tests/main.swift:\(line))")
    }
}

func makePasteboard() -> NSPasteboard {
    NSPasteboard(name: NSPasteboard.Name("CopybackSelfTest-\(UUID().uuidString)"))
}

func makeTempDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("CopybackSelfTest-\(UUID().uuidString)")
    try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

func write(_ types: [(NSPasteboard.PasteboardType, Data)], to pasteboard: NSPasteboard) {
    let item = NSPasteboardItem()
    for (type, data) in types {
        item.setData(data, forType: type)
    }
    pasteboard.clearContents()
    pasteboard.writeObjects([item])
}

func pngData(width: Int, height: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    return rep.representation(using: .png, properties: [:])!
}

func fileCount(in directory: URL, _ subdirectory: String) -> Int {
    (try? FileManager.default.contentsOfDirectory(atPath: directory.appendingPathComponent(subdirectory).path).count) ?? -1
}

MainActor.assumeIsolated {
    print("PasteboardCodec")
    do {
        let source = makePasteboard()
        let rtf = Data("{\\rtf1\\ansi {\\b hello} world}".utf8)
        write([(.rtf, rtf), (.html, Data("<b>hello</b> world".utf8)), (.string, Data("hello world".utf8))], to: source)
        let snapshot = PasteboardCodec.snapshot(of: source)
        expect(snapshot?.kind == .text, "서식 있는 텍스트를 텍스트로 인식")
        expect(snapshot?.text == "hello world", "표시 텍스트는 일반 텍스트")

        let target = makePasteboard()
        PasteboardCodec.write(snapshot?.items ?? [], to: target)
        expect(target.string(forType: .string) == "hello world", "다시 복사: 일반 텍스트 복원")
        expect(target.data(forType: .rtf) == rtf, "다시 복사: RTF 서식 복원")
        expect(PasteboardCodec.snapshot(of: target)?.items == snapshot?.items, "다시 복사: 타입 순서·데이터 동일")
        source.releaseGlobally()
        target.releaseGlobally()
    }
    do {
        let pasteboard = makePasteboard()
        write([(.string, Data("secret".utf8)),
               (NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"), Data())], to: pasteboard)
        expect(PasteboardCodec.snapshot(of: pasteboard) == nil, "비밀번호 관리자 표시(ConcealedType)는 무시")

        write([(.string, Data("hi".utf8)),
               (NSPasteboard.PasteboardType("com.apple.pasteboard.promised-file-url"), Data("x".utf8))], to: pasteboard)
        let types = PasteboardCodec.snapshot(of: pasteboard)?.items.flatMap { $0.map(\.type) } ?? []
        expect(types == [NSPasteboard.PasteboardType.string.rawValue], "파일 프로미스 타입은 저장 안 함")

        write([(.string, Data("big".utf8)),
               (NSPasteboard.PasteboardType("com.example.huge"), Data(count: PasteboardCodec.maxSnapshotBytes + 1))], to: pasteboard)
        let bigTypes = PasteboardCodec.snapshot(of: pasteboard)?.items.flatMap { $0.map(\.type) } ?? []
        expect(bigTypes == [NSPasteboard.PasteboardType.string.rawValue], "너무 크면 필수 타입만 저장")

        write([(.string, Data(repeating: UInt8(ascii: "a"), count: PasteboardCodec.maxSnapshotBytes + 1))], to: pasteboard)
        expect(PasteboardCodec.snapshot(of: pasteboard) == nil, "필수 타입만으로도 너무 크면 기록 안 함")
        pasteboard.releaseGlobally()
    }
    do {
        let pasteboard = makePasteboard()
        let png = pngData(width: 300, height: 200)
        write([(.png, png)], to: pasteboard)
        let snapshot = PasteboardCodec.snapshot(of: pasteboard)
        expect(snapshot?.kind == .image, "이미지 인식")
        expect(snapshot?.text == "이미지 300×200", "이미지 설명 텍스트")
        let thumbnail = snapshot?.thumbnailPNG.flatMap { NSBitmapImageRep(data: $0) }
        expect(thumbnail.map { max($0.pixelsWide, $0.pixelsHigh) } == 128, "썸네일 128px로 축소")
        expect(PasteboardCodec.thumbnailPNG(ofImageData: png, maxSourcePixels: 300 * 200 - 1) == nil,
               "화소가 너무 많은 이미지는 썸네일 생략")
        pasteboard.releaseGlobally()
    }
    do {
        let pasteboard = makePasteboard()
        let directory = makeTempDirectory()
        let files = [directory.appendingPathComponent("a.txt"), directory.appendingPathComponent("b.txt")]
        for file in files {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(files.map { $0 as NSURL })
        let snapshot = PasteboardCodec.snapshot(of: pasteboard)
        expect(snapshot?.kind == .files, "파일 인식")
        expect(snapshot?.text == files.map(\.path).joined(separator: "\n"), "파일 경로 목록")
        expect(snapshot?.items.count == 2, "파일마다 pasteboard 항목 유지")
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    print("ClipboardHistory")
    do {
        let pasteboard = makePasteboard()
        let directory = makeTempDirectory()
        let history = ClipboardHistory(pasteboard: pasteboard, storage: HistoryStorage(directory: directory), maxItems: 3)
        @MainActor func copyText(_ text: String) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            history.checkPasteboard()
        }

        copyText("one")
        copyText("two")
        expect(history.items.map(\.text) == ["two", "one"], "최근 항목이 맨 위")
        copyText("one")
        expect(history.items.map(\.text) == ["one", "two"], "같은 내용은 중복 없이 맨 위로")
        history.checkPasteboard()
        expect(history.items.count == 2, "클립보드 변화 없으면 기록 안 함")

        let two = history.items[1]
        expect(history.copyToPasteboard(two), "기록 항목 다시 복사")
        expect(pasteboard.string(forType: .string) == "two", "클립보드에 내용 복원")
        history.checkPasteboard()
        expect(history.items.map(\.text) == ["two", "one"], "다시 복사한 항목은 맨 위, 새 기록으로 안 잡힘")

        copyText("three")
        copyText("four")
        expect(history.items.map(\.text) == ["four", "three", "two"], "최대 개수 유지")
        expect(fileCount(in: directory, "blobs") == 3, "밀려난 항목의 파일 삭제")

        let reloaded = ClipboardHistory(pasteboard: pasteboard, storage: HistoryStorage(directory: directory))
        expect(reloaded.items == history.items, "재실행 후에도 기록 유지")

        history.remove(history.items[0])
        expect(history.items.map(\.text) == ["three", "two"], "항목 삭제")
        history.removeUnpinned()
        expect(history.items.isEmpty && fileCount(in: directory, "blobs") == 0, "모두 지우기")
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
    do {
        let pasteboard = makePasteboard()
        let directory = makeTempDirectory()
        let storage = HistoryStorage(directory: directory)
        let excluded = try? directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup
        expect(excluded == true, "기록 폴더는 Time Machine 백업 제외")

        let stray = storage.blobURL(for: UUID())
        FileManager.default.createFile(atPath: stray.path, contents: Data("leftover".utf8))
        _ = ClipboardHistory(pasteboard: pasteboard, storage: storage)
        expect(!FileManager.default.fileExists(atPath: stray.path), "시작할 때 목록에 없는 파일 정리")

        FileManager.default.createFile(atPath: stray.path, contents: Data("leftover".utf8))
        try? Data("not json".utf8).write(to: directory.appendingPathComponent("history.json"))
        let recovered = ClipboardHistory(pasteboard: pasteboard, storage: storage)
        let backups = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { $0.hasPrefix("history.corrupt-") } ?? []
        expect(recovered.items.isEmpty && backups.count == 1, "깨진 목록은 백업 후 빈 목록으로 시작")
        expect(FileManager.default.fileExists(atPath: stray.path), "목록이 깨졌을 땐 데이터 파일을 지우지 않음")

        recovered.removeUnpinned()
        let remaining = (try? FileManager.default.contentsOfDirectory(atPath: directory.path))?
            .filter { $0.hasPrefix("history.corrupt-") } ?? ["?"]
        expect(fileCount(in: directory, "blobs") == 0 && remaining.isEmpty, "모두 지우기는 남은 파일·백업까지 삭제")
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    print("고정(pin)")
    do {
        let pasteboard = makePasteboard()
        let directory = makeTempDirectory()
        let history = ClipboardHistory(pasteboard: pasteboard, storage: HistoryStorage(directory: directory), maxItems: 2)
        @MainActor func copyText(_ text: String) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            history.checkPasteboard()
        }
        @MainActor func item(_ text: String) -> ClipItem {
            history.items.first { $0.text == text }!
        }

        copyText("keep")
        copyText("a")
        history.setPinned(true, for: item("keep"))
        copyText("b")
        copyText("c")
        expect(history.items.map(\.text) == ["c", "b", "keep"], "고정 항목은 개수 제한으로 밀려나지 않음")
        copyText("keep")
        expect(history.items.first?.text == "keep" && item("keep").isPinned, "같은 내용을 다시 복사해도 고정 유지")

        let model = PanelModel(history: history)
        expect(model.visibleItems.map(\.text) == ["keep", "c", "b"], "고정 항목이 목록 맨 위")
        model.togglePin(item("b"))
        expect(model.visibleItems.map(\.text) == ["keep", "b", "c"], "고정한 순서대로 위에 표시")
        model.copy(at: 0)
        expect(pasteboard.string(forType: .string) == "keep", "⌘1은 첫 번째 고정 항목")

        let reloaded = ClipboardHistory(pasteboard: pasteboard, storage: HistoryStorage(directory: directory))
        expect(reloaded.items.filter(\.isPinned).map(\.text).sorted() == ["b", "keep"], "재실행 후에도 고정 유지")

        history.setPinned(false, for: item("keep"))
        expect(history.items.first?.text == "keep" && !item("keep").isPinned, "고정 해제하면 최근 기록 맨 위로")

        history.removeUnpinned()
        expect(history.items.map(\.text) == ["b"] && fileCount(in: directory, "blobs") == 1, "모두 지우기는 고정 항목만 남김")

        let legacy = #"[{"id":"\#(UUID().uuidString)","kind":"text","date":0,"text":"old","contentHash":"h"}]"#
        let decoded = try? JSONDecoder().decode([ClipItem].self, from: Data(legacy.utf8))
        expect(decoded?.first?.isPinned == false, "고정 필드가 없는 예전 기록 파일도 읽힘")
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }

    print("PanelModel")
    do {
        let pasteboard = makePasteboard()
        let directory = makeTempDirectory()
        let history = ClipboardHistory(pasteboard: pasteboard, storage: HistoryStorage(directory: directory))
        for text in ["Apple juice", "banana", "apple pie"] {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            history.checkPasteboard()
        }
        let model = PanelModel(history: history)
        var finished = 0
        model.onFinish = { finished += 1 }

        model.query = "APPLE"
        expect(model.visibleItems.map(\.text) == ["apple pie", "Apple juice"], "대소문자 무시 검색")
        expect(model.selectedItem?.text == "apple pie", "검색하면 첫 결과 선택")
        model.moveSelection(by: 1)
        model.moveSelection(by: 1)
        expect(model.selectedItem?.text == "Apple juice", "아래 화살표는 마지막에서 멈춤")
        model.copySelected()
        expect(pasteboard.string(forType: .string) == "Apple juice" && finished == 1, "Enter로 선택 항목 복사")

        model.query = ""
        model.copy(at: 2)
        expect(pasteboard.string(forType: .string) == "banana", "⌘3으로 세 번째 항목 복사")
        model.selectedID = history.items[0].id
        model.deleteSelected()
        expect(!history.items.contains { $0.text == "banana" }, "선택 항목 삭제")
        expect(model.selectedItem?.text == history.items.first?.text, "삭제 후 다음 항목 선택")
        pasteboard.releaseGlobally()
        try? FileManager.default.removeItem(at: directory)
    }
}

print(failures == 0 ? "\n모든 검사 통과" : "\n실패 \(failures)건")
exit(failures == 0 ? 0 : 1)
