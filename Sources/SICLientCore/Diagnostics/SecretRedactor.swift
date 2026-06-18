import Foundation

public enum SecretRedactor {
  private static let patterns: [(name: String, regex: NSRegularExpression)] = {
        let rawPatterns = [
            #"(?i)\bRES=([0-9a-fA-F]+)"#,
            #"(?i)\bIK=([0-9a-fA-F]+)"#,
            #"(?i)\bCK=([0-9a-fA-F]+)"#,
            #"(?i)\bAUTN=([0-9a-fA-F]+)"#,
            #"(?i)\bAUTS=([0-9a-fA-F]+)"#,
            #"(?i)\bRAND=([0-9a-fA-F]+)"#,
            #"(?i)response=\"?([0-9a-fA-F]{8,})\"?"#,
            #"(?i)nonce=\"?([0-9a-fA-F]{8,})\"?"#,
            #"(?i)"(ck|ik|res|autn|auts|rand)":\s*"([0-9a-fA-F]{8,})""#,
        ]

        return rawPatterns.compactMap { pattern in
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
            return (pattern, regex)
        }
    }()

    public static func redact(_ input: String) -> String {
        var result = input
        for (_, regex) in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                range: range,
                withTemplate: "[REDACTED]"
            )
        }
        return result
    }

    private static let sensitiveFieldKeys: Set<String> = [
        "res", "ik", "ck", "autn", "auts", "rand", "nonce", "response",
    ]

    public static func redactField(key: String, value: String) -> String {
        if sensitiveFieldKeys.contains(key.lowercased()) {
            return "[REDACTED]"
        }
        return redact(value)
    }

    public static func containsSensitiveMaterial(_ input: String) -> Bool {
        for (_, regex) in patterns {
            let range = NSRange(input.startIndex..., in: input)
            if regex.firstMatch(in: input, range: range) != nil {
                return true
            }
        }
        return false
    }
}
