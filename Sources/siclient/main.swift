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
    let emergencyCall: Bool
    let emergencyDestination: String?
    let smsDestination: String?
    let smsText: String?
    let fetchCallForwarding: Bool
    let setCallForwardingTarget: String?
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
      --call-duration <sec>  Seconds to keep MO/emergency call active (default: 2)
      --hold                 Hold then resume during MO call
      --dtmf <digit>         Send DTMF digit during MO call (0-9, *, #)
      --emergency-call [uri] Emergency register + call (default tel:112)
      --send-sms <dest> <text>  Send SMS over IMS after register
      --fetch-call-forwarding  Read unconditional call forwarding via XCAP
      --set-call-forwarding <target>  Enable CFU to target via XCAP
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
    var emergencyCall = false
    var emergencyDestination: String?
    var smsDestination: String?
    var smsText: String?
    var fetchCallForwarding = false
    var setCallForwardingTarget: String?

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
        case "--fetch-call-forwarding":
            fetchCallForwarding = true
            index += 1
        case "--emergency-call":
            emergencyCall = true
            if index + 1 < arguments.count, !arguments[index + 1].hasPrefix("--") {
                emergencyDestination = arguments[index + 1]
                index += 2
            } else {
                index += 1
            }
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
        case "--send-sms":
            guard index + 2 < arguments.count else {
                throw CLIError.missingArgument("--send-sms")
            }
            smsDestination = arguments[index + 1]
            smsText = arguments[index + 2]
            index += 3
        case "--set-call-forwarding":
            guard index + 1 < arguments.count else {
                throw CLIError.missingArgument("--set-call-forwarding")
            }
            setCallForwardingTarget = arguments[index + 1]
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
        dtmfDigit: dtmfDigit,
        emergencyCall: emergencyCall,
        emergencyDestination: emergencyDestination,
        smsDestination: smsDestination,
        smsText: smsText,
        fetchCallForwarding: fetchCallForwarding,
        setCallForwardingTarget: setCallForwardingTarget
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
                    dtmfDigit: options.dtmfDigit,
                    emergencyCall: options.emergencyCall,
                    emergencyDestination: options.emergencyDestination,
                    smsDestination: options.smsDestination,
                    smsText: options.smsText,
                    fetchCallForwarding: options.fetchCallForwarding,
                    setCallForwardingTarget: options.setCallForwardingTarget
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
