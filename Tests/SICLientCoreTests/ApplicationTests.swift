import Foundation
import Testing
@testable import SICLientCore

@Test func applicationDryRunEmitsStructuredLog() async throws {
    let profileURL = fixtureURL(named: "lab-volte-01.json")
    let collector = LineCollector()

    let app = Application(
        options: ApplicationOptions(profilePath: profileURL.path, dryRun: true),
        output: { collector.append($0) }
    )

    try await app.run()

    let lines = collector.snapshot
    let bootstrapLine = try #require(lines.first { $0.contains("bootstrap complete") })
    #expect(bootstrapLine.contains("\"level\":\"info\""))
    #expect(bootstrapLine.contains("lab-volte-01"))
    #expect(!bootstrapLine.contains("e19aa1c37ab954daa44fa2a52007"))
}
