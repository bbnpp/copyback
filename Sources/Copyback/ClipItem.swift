import Foundation

/// 기록 한 건의 메타데이터. 클립보드 원본 데이터는 HistoryStorage가 별도 파일(blob)로 저장한다.
struct ClipItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text, image, files
    }

    let id: UUID
    var kind: Kind
    var date: Date
    /// 목록 표시·검색용 텍스트 (텍스트 앞부분, 줄바꿈으로 구분한 파일 경로, 이미지 설명)
    var text: String
    /// 중복 판별용 해시. 같은 내용을 다시 복사하면 기존 항목을 맨 위로 올린다.
    var contentHash: String
    var appName: String?
    var appBundleID: String?
}

/// NSPasteboardItem 하나에 담긴 타입 하나와 그 데이터. 배열 순서 = 원본 타입 순서.
struct PasteboardEntry: Codable, Equatable {
    var type: String
    var data: Data
}
