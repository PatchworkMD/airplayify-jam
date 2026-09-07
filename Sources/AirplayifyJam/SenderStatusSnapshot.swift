import Foundation

struct SenderStatusSnapshot: Codable, Equatable, Sendable {
    enum State: String, Codable, Sendable {
        case starting
        case ready
        case failed
    }

    let state: State
    let detail: String

    static func decode(_ data: Data) -> SenderStatusSnapshot? {
        try? JSONDecoder().decode(SenderStatusSnapshot.self, from: data)
    }
}
