import Foundation

/// 3GPP TS 24.341 RP-DATA envelope for SMS over IMS (lab subset).
public enum SMSPayloadBuilder {
    public static func rpData(userData: String, destination: String) -> Data {
        let tpdu = "0400\(String(format: "%02X", min(userData.utf8.count, 140)))\(userData.utf8.map { String(format: "%02X", $0) }.joined())"
        let rpdu = "000000\(destination.filter(\.isNumber).prefix(15))"
        let envelope = "RP-DATA \(rpdu) \(tpdu)"
        return Data(envelope.utf8)
    }
}
