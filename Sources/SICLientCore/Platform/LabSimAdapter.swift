import Foundation

public struct LabSimAdapter: SimAdapter {
    private let config: LabSimConfig

    public init(config: LabSimConfig) {
        self.config = config
    }

    public func getIMPI() throws -> String {
        config.impi
    }

    public func getIMPUList() throws -> [String] {
        config.impus
    }

    public func akaChallenge(rand: Data, autn: Data) throws -> AKAChallengeResult {
        let randHex = rand.hexLowercase
        let autnHex = autn.hexLowercase

        if let vector = config.akaVectors.first(where: {
            $0.rand.lowercased() == randHex && $0.autn.lowercased() == autnHex
        }) {
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
    var hexLowercase: String {
        map { String(format: "%02x", $0) }.joined()
    }

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
