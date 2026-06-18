import Foundation
import Testing
@testable import SICLientCore

@Test func redactsAuthorizationResponse() {
    let input = #"Authorization: Digest response="e19aa1c37ab954daa44fa2a52007", nonce="235a551d""#
    let redacted = SecretRedactor.redact(input)
    #expect(!redacted.contains("e19aa1c37ab954daa44fa2a52007"))
    #expect(redacted.contains("[REDACTED]"))
}

@Test func redactsJSONKeyMaterial() {
    let input = #"{"ik":"4f44282041c2e6f9277be486541a48f1","ck":"a746f0f8e465d622812a466f34a9b610"}"#
    let redacted = SecretRedactor.redact(input)
    #expect(!redacted.contains("4f44282041c2e6f9277be486541a48f1"))
    #expect(!redacted.contains("a746f0f8e465d622812a466f34a9b610"))
}

@Test func loggerSanitizesFields() throws {
    let collector = LineCollector()
    let logger = Logger(output: { collector.append($0) })

    logger.info(
        "aka complete",
        fields: [
            "res": "e19aa1c37ab954daa44fa2a52007",
            "status": "ok",
        ]
    )

    let lines = collector.snapshot
    let line = try #require(lines.first)
    #expect(!line.contains("e19aa1c37ab954daa44fa2a52007"))
    #expect(line.contains("bootstrap-") || line.contains("run-") || line.contains("correlation_id"))
}

@Test func correlationIDHasPrefix() {
    let id = CorrelationID(prefix: "reg")
    #expect(id.value.hasPrefix("reg-"))
}
