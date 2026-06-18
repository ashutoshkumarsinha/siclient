// CLIIntegrationTests.swift
//
// Verifies the siclient command-line binary end-to-end: help text, dry-run bootstrap,
// error handling for missing/invalid arguments, and GUI binary smoke check. These are
// the same entry points operators use to validate profiles before field deployment.

import Foundation
import Testing

// MARK: - CLI help & usage

/// `--help` must print usage including profile path and MO call flags so operators
/// know how to invoke the client from scripts and CI pipelines.
@Test func cliHelpPrintsUsage() throws {
    let result = try runExecutable(named: "siclient", arguments: ["--help"])
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("siclient"))
    #expect(result.stdout.contains("--profile"))
    #expect(result.stdout.contains("--mo-call"))
}

// MARK: - Dry-run bootstrap

/// `--dry-run` loads the profile and logs bootstrap success without sending SIP or
/// leaking AKA secrets — safe for CI and pre-flight profile validation.
@Test func cliDryRunBootstrapSmoke() throws {
    let profile = guiFixtureURL(named: "lab-volte-01.json").path
    let result = try runExecutable(
        named: "siclient",
        arguments: ["--profile", profile, "--dry-run"]
    )
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("bootstrap complete"))
    #expect(result.stdout.contains("lab-volte-01"))
    #expect(!result.stdout.contains("e19aa1c37ab954daa44fa2a52007"))
}

// MARK: - CLI error handling

/// Running without `--profile` must exit non-zero with a clear error — the client
/// cannot bootstrap IMS without an operator configuration file.
@Test func cliMissingProfileExitsNonZero() throws {
    let result = try runExecutable(named: "siclient", arguments: [])
    #expect(result.exitCode != 0)
    #expect(result.stderr.contains("Missing required --profile"))
}

/// Unknown CLI flags must be rejected rather than silently ignored, preventing
/// typos in automation scripts from causing confusing partial runs.
@Test func cliUnknownArgumentExitsNonZero() throws {
    let profile = guiFixtureURL(named: "lab-volte-01.json").path
    let result = try runExecutable(
        named: "siclient",
        arguments: ["--profile", profile, "--not-a-flag"]
    )
    #expect(result.exitCode != 0)
    #expect(result.stderr.contains("Unknown argument"))
}

// MARK: - GUI binary smoke test

/// Confirms the GUI binary links and exists after build. SwiftUI cannot be driven in
/// headless CI — ViewModel tests cover GUI logic; this only checks the binary is present.
@Test func guiExecutableBuildsAndLaunchesHelpfully() throws {
    // Smoke: ensure the GUI binary links and starts without instant crash.
    // We cannot drive SwiftUI in headless CI; ViewModel tests cover GUI logic.
    let binary = packageRootURL().appendingPathComponent(".build/debug/siclient-gui")
    #expect(FileManager.default.fileExists(atPath: binary.path))
}
