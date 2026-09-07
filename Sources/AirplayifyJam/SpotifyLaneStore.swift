import Foundation

struct SpotifyLaneStore {
    private let url: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        let baseDirectory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        self.url = baseDirectory.appendingPathComponent("AirplayifyJam/spotify-profiles.json")
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func load() -> [SpotifyProfile] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? decoder.decode([SpotifyProfile].self, from: data)) ?? []
    }

    func save(_ profiles: [SpotifyProfile]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try encoder.encode(profiles)
        try data.write(to: url, options: .atomic)
    }
}
