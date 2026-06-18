# ADR 0001: Swift on macOS Tahoe and SIP Stack Strategy

## Status

Accepted (Phase 0)

## Context

The IMS SIP Client spec originally assumed C/C++ or Rust. The project now targets **macOS Tahoe (26)** for development and lab interop, with Swift 6 as the implementation language.

We need decisions on:

1. Build system and module layout
2. SIP stack approach for Phase 1
3. Security transport path for initial lab register

## Decision

### 1. Language & Platform

- **Swift 6** with Swift Package Manager
- Minimum platform: **macOS 26 (Tahoe)**
- Executable: `siclient` CLI; library: `SICLientCore`

### 2. SIP Stack (Phase 1)

**Decision: In-house Swift SIP message layer for Phase 1 REGISTER path; evaluate wrapping C libs only if parser effort blocks schedule.**

| Option | Pros | Cons |
|---|---|---|
| **PJSIP (C)** | Battle-tested, IPSec helpers | C bridge, memory model, macOS packaging |
| **reSIProcate (C++)** | Strong SIP compliance | Heavy C++ interop |
| **Sofia-SIP (C)** | Lightweight | Less active maintenance |
| **Native Swift (chosen for P1 start)** | Idiomatic, Sendable, testable | More implementation work |

Phase 1 scope is narrow (REGISTER + headers). A focused RFC 3261 subset in Swift is acceptable. Revisit if MO/MT INVITE parsing slips past Week 5.

### 3. Security Transport (Phase 1 exit)

**Decision: TLS-first lab profile; IPSec-3GPP parallel track.**

macOS does not expose 3GPP IPSec-UE APIs. `profiles/lab-volte-01.json` defaults to `"mechanism": "tls"`. IPSec will be stubbed with an ADR amendment when a test harness is available.

### 4. SIM / IMS-AKA

**Decision: `LabSimAdapter` with profile-embedded AKA vectors for CI; no MILENAGE in Phase 0.**

Production `SimAdapter` implementations are out of scope until hardware or HSS integration exists.

## Consequences

- Fast Phase 0 delivery on Tahoe without C toolchain friction
- Phase 1 owns SIP parser risk — mitigated by SIPp conformance tests
- IPSec may lag TLS for lab exit; spec exit gate allows TLS-only (see spec Section 10)
