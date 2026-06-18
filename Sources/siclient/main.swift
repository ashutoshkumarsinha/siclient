import Foundation
import SICLientCore

struct CLIOptions {
    let profilePath: String
    let dryRun: Bool
    let deregister: Bool
    let moCallDestination: String?
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
      siclient --profile <path> [--dry-run] [--deregister] [--mo-call <sip-uri>]

    Options:
      --profile <path>     Operator profile JSON file (required)
      --dry-run            Load profile and adapters without starting signaling
      --deregister         Register then send Expires: 0 deregister
      --mo-call <uri>      Register, place MO VoLTE call, then hang up
      -h, --help           Show this help message
    """
    print(text)
}

func parseArguments(_ arguments: [String]) throws -> CLIOptions {
    var profilePath: String?
    var dryRun = false
    var deregister = false
    var moCallDestination: String?

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
        case "--mo-call":
            guard index + 1 < arguments.count else {
                throw CLIError.missingArgument("--mo-call")
            }
            moCallDestination = arguments[index + 1]
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

    return CLIOptions(profilePath: profilePath, dryRun: dryRun, deregister: deregister, moCallDestination: moCallDestination)
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
                    moCallDestination: options.moCallDestination
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
