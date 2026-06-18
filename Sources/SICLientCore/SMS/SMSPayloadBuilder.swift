import Foundation

// MARK: - File Overview
// Wraps user text in a 3GPP RP-DATA envelope for SMS-over-IMS. RP-DATA is the relay
// layer message that carries the actual SMS user data inside a SIP MESSAGE body.

/// 3GPP TS 24.341 RP-DATA envelope for SMS over IMS (lab subset).
public enum SMSPayloadBuilder {
    /// Builds a lab RP-DATA payload containing user text and destination digits.
    public static func rpData(userData: String, destination: String) -> Data {
        let tpdu = "0400\(String(format: "%02X", min(userData.utf8.count, 140)))\(userData.utf8.map { String(format: "%02X", $0) }.joined())"
        let rpdu = "000000\(destination.filter(\.isNumber).prefix(15))"
        let envelope = "RP-DATA \(rpdu) \(tpdu)"
        return Data(envelope.utf8)
    }
}
