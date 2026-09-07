import Foundation

enum RuntimePaths {
    static var sourceRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static var resources: URL {
        Bundle.main.resourceURL ?? sourceRoot
    }

    static func resource(_ relativePath: String) -> URL {
        let bundled = resources.appendingPathComponent(relativePath)
        if Bundle.main.resourceURL != nil, FileManager.default.fileExists(atPath: bundled.path) { return bundled }
        return sourceRoot.appendingPathComponent(relativePath)
    }
}
