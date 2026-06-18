import Foundation
import SICLientCore
import SICLientGUI

func guiFixtureURL(named name: String) -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("../profiles/\(name)")
        .standardizedFileURL
}

func loadGUIFixtureProfile() throws -> OperatorProfile {
    try ProfileLoader.load(from: guiFixtureURL(named: "lab-volte-01.json"))
}

func makeLabLoopbackTransport(
    profile: OperatorProfile
) -> (LoopbackSIPTransport, MockPCSCFState, MockIMSState) {
    let pcscfState = MockPCSCFState()
    let imsState = MockIMSState()
    let fixedProfile = profile
    let transport = LoopbackSIPTransport { data in
        guard case .request(let request) = try? SIPParser.parse(data) else { return [] }
        if request.method == SIPMethod.register.rawValue {
            guard let response = MockPCSCFResponder.response(for: data, profile: fixedProfile, state: pcscfState) else {
                return []
            }
            return [response]
        }
        return MockIMSResponder.responses(for: data, profile: fixedProfile, state: imsState)
    }
    return (transport, pcscfState, imsState)
}

@MainActor
func makeGUIViewModel(profile: OperatorProfile) throws -> ClientViewModel {
    let (transport, _, _) = makeLabLoopbackTransport(profile: profile)
    let logger = Logger(output: { _ in })
    let platform = try PlatformContext.stubbed(profile: profile)
    let service = CallService(
        profile: profile,
        platform: platform,
        transport: transport,
        logger: logger,
        enableMedia: false
    )
    return ClientViewModel(profile: profile, callService: service)
}

func packageRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .standardizedFileURL
}

@discardableResult
func runExecutable(
    named name: String,
    arguments: [String],
    timeout: TimeInterval = 30
) throws -> (exitCode: Int32, stdout: String, stderr: String) {
    let binary = packageRootURL()
        .appendingPathComponent(".build/debug/\(name)")
    guard FileManager.default.fileExists(atPath: binary.path) else {
        throw GUITestError.binaryNotBuilt(name)
    }

    let process = Process()
    process.executableURL = binary
    process.arguments = arguments

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    try process.run()

    let deadline = Date().addingTimeInterval(timeout)
    while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
    }
    if process.isRunning {
        process.terminate()
        throw GUITestError.timeout(name)
    }

    let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    return (process.terminationStatus, stdout, stderr)
}

enum GUITestError: Error, CustomStringConvertible {
    case binaryNotBuilt(String)
    case timeout(String)

    var description: String {
        switch self {
        case .binaryNotBuilt(let name):
            return "Executable not built: \(name) — run swift build first"
        case .timeout(let name):
            return "Timed out running \(name)"
        }
    }
}
