import Foundation
@testable import SICLientCore

final class LineCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var lines: [String] = []

    func append(_ line: String) {
        lock.lock()
        defer { lock.unlock() }
        lines.append(line)
    }

    var snapshot: [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}

func fixtureURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../profiles/\(name)")
        .standardizedFileURL
}

func loadFixtureProfile() throws -> OperatorProfile {
    try ProfileLoader.load(from: fixtureURL(named: "lab-volte-01.json"))
}
