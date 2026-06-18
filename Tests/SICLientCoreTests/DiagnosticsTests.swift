// DiagnosticsTests.swift
//
// Verifies logging, secret redaction, and correlation IDs used when debugging IMS
// registration and call flows. AKA responses, IK/CK keys, and Digest credentials must
// never appear in plaintext logs — the same requirement carriers enforce in production.

import Foundation
import Testing
@testable import SICLientCore

// MARK: - Secret redaction

/// SIP Authorization headers contain the AKA response digest; logs must replace it
/// with [REDACTED] so packet captures and log files stay safe to share.
@Test func redactsAuthorizationResponse() {
    let input = #"Authorization: Digest response="e19aa1c37ab954daa44fa2a52007", nonce="235a551d""#
    let redacted = SecretRedactor.redact(input)
    #expect(!redacted.contains("e19aa1c37ab954daa44fa2a52007"))
    #expect(redacted.contains("[REDACTED]"))
}

/// IK and CK session keys from AKA must also be scrubbed from JSON diagnostic output.
@Test func redactsJSONKeyMaterial() {
    let input = #"{"ik":"4f44282041c2e6f9277be486541a48f1","ck":"a746f0f8e465d622812a466f34a9b610"}"#
    let redacted = SecretRedactor.redact(input)
    #expect(!redacted.contains("4f44282041c2e6f9277be486541a48f1"))
    #expect(!redacted.contains("a746f0f8e465d622812a466f34a9b610"))
}

// MARK: - Structured logging

/// The Logger must sanitize sensitive field values before writing structured JSON,
/// while still attaching a correlation ID so engineers can trace one registration
/// attempt across multiple log lines.
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

/// Correlation IDs group related SIP transactions (e.g. all messages in one REGISTER
/// flow) so support teams can filter logs by registration, call, or bootstrap phase.
@Test func correlationIDHasPrefix() {
    let id = CorrelationID(prefix: "reg")
    #expect(id.value.hasPrefix("reg-"))
}
