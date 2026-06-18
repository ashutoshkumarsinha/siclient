// ApplicationTests.swift
//
// Verifies the top-level Application entry point that wires together profile loading,
// platform bootstrap, and structured logging. In a real IMS deployment this is the
// same path the CLI or GUI uses to start a VoLTE session against a P-CSCF.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Bootstrap & dry-run

/// Confirms that `--dry-run` loads a lab profile and emits JSON logs without touching
/// the network or leaking AKA secrets. Operators rely on dry-run to validate profiles
/// before attaching to a live IMS core.
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
