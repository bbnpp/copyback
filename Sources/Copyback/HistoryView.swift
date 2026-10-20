import SwiftUI

enum PanelLayout {
    static let width: CGFloat = 380
    static let height: CGFloat = 480
}

struct HistoryView: View {
    @ObservedObject var model: PanelModel
    @ObservedObject var history: ClipboardHistory
    @FocusState private var searchFocused: Bool
    @State private var confirmingClear = false

    var body: some View {
        let items = model.visibleItems
        let selectedID = model.selectedItem(in: items)?.id

        VStack(spacing: 0) {
            searchField
            Divider()
            if items.isEmpty {
                emptyState
            } else {
                list(items, selectedID: selectedID)
            }
            Divider()
            footer
        }
        .frame(width: PanelLayout.width, height: PanelLayout.height)
        .onAppear { searchFocused = true }
        .onChange(of: model.focusRequest) {
            searchFocused = true
            confirmingClear = false
        }
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("검색", text: $model.query)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !model.query.isEmpty {
                Button {
                    model.query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func list(_ items: [ClipItem], selectedID: ClipItem.ID?) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if let title = sectionTitle(at: index, in: items) {
                            Text(title)
                                .font(.system(size: 10.5, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8)
                                .padding(.top, index == 0 ? 2 : 8)
                        }
                        ClipRow(item: item, model: model,
                                shortcut: index < 9 ? index + 1 : nil,
                                isSelected: item.id == selectedID)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture { model.copy(item) }
                            .contextMenu {
                                Button("복사") { model.copy(item) }
                                Button(item.isPinned ? "고정 해제" : "고정") { model.togglePin(item) }
                                Button("삭제", role: .destructive) { model.delete(item) }
                            }
                    }
                }
                .padding(6)
            }
            .onChange(of: model.scrollTarget) { _, target in
                if let target { proxy.scrollTo(target) }
            }
        }
    }

    /// 고정 항목이 있을 때만 "고정됨" / "최근" 구역 제목을 붙인다
    private func sectionTitle(at index: Int, in items: [ClipItem]) -> String? {
        guard items.first?.isPinned == true else { return nil }
        if index == 0 { return "고정됨" }
        return !items[index].isPinned && items[index - 1].isPinned ? "최근" : nil
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text(model.query.isEmpty ? "복사한 내용이 여기에 쌓입니다" : "검색 결과가 없습니다")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if confirmingClear {
                Text("고정 안 한 기록을 모두 지울까요?")
                Spacer()
                Button("취소") { confirmingClear = false }
                Button("모두 지우기") {
                    model.clearAll()
                    confirmingClear = false
                }
                .foregroundStyle(.red)
            } else {
                Text("\(history.items.count)개 · ⏎ 복사 · ⌘P 고정 · ⌘⌫ 삭제")
                    .foregroundStyle(.secondary)
                Spacer()
                Button("모두 지우기") { confirmingClear = true }
                    .disabled(!history.items.contains { !$0.isPinned })
                settingsMenu
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
    }

    private var settingsMenu: some View {
        Menu {
            Toggle("로그인 시 자동 실행", isOn: Binding(
                get: { model.launchAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            Divider()
            Button("Copyback 종료") { model.quit() }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

struct ClipRow: View {
    let item: ClipItem
    let model: PanelModel
    let shortcut: Int?
    let isSelected: Bool
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 10) {
            icon
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.previewText)
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                TimelineView(.everyMinute) { context in
                    Text(subtitle(now: context.date))
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(45))
                    .foregroundStyle(.secondary)
            }
            if let shortcut {
                Text("⌘\(shortcut)")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.22) : Color.primary.opacity(isHovered ? 0.06 : 0))
        )
        .onHover { isHovered = $0 }
    }

    @ViewBuilder private var icon: some View {
        switch item.kind {
        case .image:
            if let thumbnail = model.thumbnail(for: item) {
                Image(nsImage: thumbnail)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 32, height: 32)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            } else {
                symbol("photo")
            }
        case .files:
            Image(nsImage: model.fileIcon(path: item.filePaths.first ?? ""))
                .resizable()
        case .text:
            if let appIcon = model.appIcon(for: item) {
                Image(nsImage: appIcon)
                    .resizable()
            } else {
                symbol("doc.text")
            }
        }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 18))
            .foregroundStyle(.secondary)
    }

    private func subtitle(now: Date) -> String {
        let time = RelativeTime.string(for: item.date, now: now)
        guard let appName = item.appName else { return time }
        return "\(appName) · \(time)"
    }
}

extension ClipItem {
    var filePaths: [String] {
        kind == .files ? text.components(separatedBy: "\n") : []
    }

    /// 목록 미리보기: 공백·줄바꿈을 한 칸으로 줄인 앞부분
    var previewText: String {
        switch kind {
        case .files:
            let names = filePaths.map { ($0 as NSString).lastPathComponent }
            return names.count > 1 ? "\(names[0]) 외 \(names.count - 1)개" : (names.first ?? "")
        case .image, .text:
            return text.prefix(500).split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
    }
}

enum RelativeTime {
    private static let formatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.unitsStyle = .short
        return formatter
    }()

    static func string(for date: Date, now: Date) -> String {
        now.timeIntervalSince(date) < 60 ? "방금" : formatter.localizedString(for: date, relativeTo: now)
    }
}
