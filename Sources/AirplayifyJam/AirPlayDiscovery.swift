import Foundation

enum AirPlayDiscovery {
    static func discover(timeout: TimeInterval = 2) -> [OutputDevice] {
        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        process.arguments = ["-B", "_airplay._tcp", "local"]
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        Thread.sleep(forTimeInterval: timeout)
        process.terminate()
        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        return parse(output)
    }

    static func parse(_ output: String) -> [OutputDevice] {
        var seen = Set<String>()
        return output.split(separator: "\n").compactMap { line in
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 7, fields[1] == "Add", let marker = fields.firstIndex(of: "_airplay._tcp.") else { return nil }
            let name = fields.dropFirst(marker + 1).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { return nil }
            return OutputDevice(id: "airplay:\(name)", name: name, kind: .airPlay)
        }
    }
}
