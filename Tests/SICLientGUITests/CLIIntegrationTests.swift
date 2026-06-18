import Foundation
import Testing

@Test func cliHelpPrintsUsage() throws {
    let result = try runExecutable(named: "siclient", arguments: ["--help"])
    #expect(result.exitCode == 0)
    #expect(result.stdout.contains("siclient"))
    #expect(result.stdout.contains("--profile"))
    #expect(result.stdout.contains("--mo-call"))
}

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

@Test func cliMissingProfileExitsNonZero() throws {
    let result = try runExecutable(named: "siclient", arguments: [])
    #expect(result.exitCode != 0)
    #expect(result.stderr.contains("Missing required --profile"))
}

@Test func cliUnknownArgumentExitsNonZero() throws {
    let profile = guiFixtureURL(named: "lab-volte-01.json").path
    let result = try runExecutable(
        named: "siclient",
        arguments: ["--profile", profile, "--not-a-flag"]
    )
    #expect(result.exitCode != 0)
    #expect(result.stderr.contains("Unknown argument"))
}

@Test func guiExecutableBuildsAndLaunchesHelpfully() throws {
    // Smoke: ensure the GUI binary links and starts without instant crash.
    // We cannot drive SwiftUI in headless CI; ViewModel tests cover GUI logic.
    let binary = packageRootURL().appendingPathComponent(".build/debug/siclient-gui")
    #expect(FileManager.default.fileExists(atPath: binary.path))
}
