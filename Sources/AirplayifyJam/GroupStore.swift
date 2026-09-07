import Foundation

struct GroupStore {
    private let url: URL

    init(directory: URL? = nil) {
        let base = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        url = base.appendingPathComponent("AirplayifyJam", isDirectory: true).appendingPathComponent("groups.json")
    }

    func load() -> [OutputGroup] {
        guard let data = try? Data(contentsOf: url),
              let groups = try? JSONDecoder().decode([OutputGroup].self, from: data) else { return [] }
        return groups
    }

    func save(_ groups: [OutputGroup]) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(groups)
        let temp = url.appendingPathExtension("tmp")
        try data.write(to: temp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temp, backupItemName: nil, options: .usingNewMetadataOnly)
        } else {
            try FileManager.default.moveItem(at: temp, to: url)
        }
    }
}
