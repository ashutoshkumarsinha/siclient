import Foundation
import SICLientCore

struct CLIOptions {
    let profilePath: String
    let dryRun: Bool
    let deregister: Bool
    let moCallDestination: String?
    let callDurationSec: Int
    let holdAfterConnect: Bool
    let dtmfDigit: Character?
}

enum CLIError: Error, CustomStringConvertible {
    case missingProfile
    case missingArgument(String)
    case unknownArgument(String)
    case helpRequested

    var description: String {
        switch self {
        case .missingProfile:
            return "Missing required --profile <path> argument"
        case .missingArgument(let arg):
            return "Missing value for \(arg)"
        case .unknownArgument(let arg):
            return "Unknown argument: \(arg)"
        case .helpRequested:
            return ""
        }
    }
}

func printUsage() {
    let text = """
    siclient — IMS SIP Client for macOS Tahoe

    Usage:
      siclient --profile <path> [options]

    Options:
      --profile <path>       Operator profile JSON file (required)
      --dry-run              Load profile and adapters without starting signaling
      --deregister           Register then send Expires: 0 deregister
      --mo-call <uri>        Register, place MO VoLTE call, then hang up
      --call-duration <sec>  Seconds to keep MO call active (default: 2)
      --hold                 Hold then resume during MO call
      --dtmf <digit>         Send DTMF digit during MO call (0-9, *, #)
      -h, --help             Show this help message
    """
    print(text)
}

func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var profilePath: String?
    var dryRun = false
    var deregister = false
    var moCallDestination: String?
    var callDurationSec = 2
    var holdAfterConnect = false
    var dtmfDigit: Character?

    var index = 1
    while index < arguments.count {
        let arg = arguments[index]
        switch arg {
        case "-h", "--help":
            printUsage()
            throw CLIError.helpRequested
        case "--dry-run":
            dryRun = true
            index += 1
        case "--deregister":
            deregister = true
            index += 1
        case "--hold":
            holdAfterConnect = true
            index += 1
        case "--mo-call":
            guard index + 1 < arguments.count else {
                throw CLIError.missingArgument("--mo-call")
            }
            moCallDestination = arguments[index + 1]
            index += 2
        case "--call-duration":
            guard index + 1 < arguments.count, let sec = Int(arguments[index + 1]) else {
                throw CLIError.missingArgument("--call-duration")
            }
            callDurationSec = sec
            index += 2
        case "--dtmf":
            guard index + 1 < arguments.count, let digit = arguments[index + 1].first else {
                throw CLIError.missingArgument("--dtmf")
            }
            dtmfDigit = digit
            index += 2
        case "--profile":
            guard index + 1 < arguments.count else {
                throw CLIError.missingProfile
            }
            profilePath = arguments[index + 1]
            index += 2
        default:
            throw CLIError.unknownArgument(arg)
        }
    }

    guard let profilePath else {
        throw CLIError.missingProfile
    }

    return CLIOptions(
        profilePath: profilePath,
        dryRun: dryRun,
        deregister: deregister,
        moCallDestination: moCallDestination,
        callDurationSec: callDurationSec,
        holdAfterConnect: holdAfterConnect,
        dtmfDigit: dtmfDigit
    )
}

@main
struct SICLientCLI {
    static func main() async {
        do {
            let options = try parseArguments(CommandLine.arguments)
            let app = Application(
                options: ApplicationOptions(
                    profilePath: options.profilePath,
                    dryRun: options.dryRun,
                    deregister: options.deregister,
                    moCallDestination: options.moCallDestination,
                    callDurationSec: options.callDurationSec,
                    holdAfterConnect: options.holdAfterConnect,
                    dtmfDigit: options.dtmfDigit
                )
            )
            try await app.run()
        } catch CLIError.helpRequested {
            return
        } catch {
            fputs("error: \(error)\n", stderr)
            exit(1)
        }
    }
}
