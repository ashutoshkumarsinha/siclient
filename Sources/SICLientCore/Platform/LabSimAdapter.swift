import Foundation

// MARK: - File overview
//
// A test SIM (Subscriber Identity Module) adapter backed by lab credentials in the
// operator profile. Answers AKA (Authentication and Key Agreement) challenges using
// pre-computed vectors instead of a real UICC card.

/// SimAdapter that serves IMPI/IMPU and AKA vectors from a lab profile JSON block.
public struct LabSimAdapter: SimAdapter {
    private let config: LabSimConfig

    /// Binds to the `lab_sim` section of an operator profile.
    public init(config: LabSimConfig) {
        self.config = config
    }

    /// Returns the lab IMPI (IP Multimedia Private Identity).
    public func getIMPI() throws -> String {
        config.impi
    }

    /// Returns the lab IMPU (IP Multimedia Public Identity) list.
    public func getIMPUList() throws -> [String] {
        config.impus
    }

    /// Looks up a matching AKA vector by RAND/AUTN and returns RES/IK/CK or AUTS.
    public func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        let randHex = rand.hexLowercase
        let autnHex = autn.hexLowercase

        if let vector = config.akaVectors.first(where: {
            $0.rand.lowercased() == randHex && $0.autn.lowercased() == autnHex
        }) {
            // AUTS present means the network expects a sync-failure resync flow
            if let autsHex = vector.auts {
                guard let auts = Data(hexString: autsHex) else {
                    throw SimAdapterError.unsupportedChallenge
                }
                return AKAChallengeResult(status: .syncFailure(auts: auts))
            }

            guard
                let res = Data(hexString: vector.res),
                let ik = Data(hexString: vector.ik),
                let ck = Data(hexString: vector.ck)
            else {
                throw SimAdapterError.unsupportedChallenge
            }

            return AKAChallengeResult(status: .success(res: res, ik: ik, ck: ck))
        }

        throw SimAdapterError.unsupportedChallenge
    }
}

extension Data {
    /// Converts raw bytes to a lowercase hex string for vector comparison.
    var hexLowercase: String {
        map { String(format: "%02x", $0) }.joined()
    }

    /// Parses a hex string (with optional non-hex characters stripped) into bytes.
    init?(hexString: String) {
        let cleaned = hexString.filter { $0.isHexDigit }
        guard !cleaned.isEmpty, cleaned.count.isMultiple(of: 2) else { return nil }

        var data = Data(capacity: cleaned.count / 2)
        var index = cleaned.startIndex
        while index < cleaned.endIndex {
            let next = cleaned.index(index, offsetBy: 2)
            guard next <= cleaned.endIndex else { return nil }
            let byte = cleaned[index ..< next]
            guard let value = UInt8(byte, radix: 16) else { return nil }
            data.append(value)
            index = next
        }
        self = data
    }
}
