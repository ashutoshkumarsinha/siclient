# SICLient

IMS SIP Client for macOS Tahoe (Swift 6). VoLTE/IMS registration, session control, media, emergency/SMS/XCAP services, and a SwiftUI lab GUI — with **122 automated tests** and novice-friendly inline documentation throughout the codebase.

## Requirements

- macOS 26 (Tahoe) or later
- Swift 6.2+ (Xcode 26 / Swift 6.3 toolchain)

## Build

```bash
make                    # build CLI + GUI (default)
make build-cli          # CLI only
make build-gui          # GUI only
swift build             # equivalent to make build
```

Or directly:

```bash
swift build                    # CLI + core library + GUI
swift build --product siclient # CLI only
swift build --product siclient-gui
```

## Test

```bash
make test               # all 122 tests
make test-core          # core only (107)
make test-gui           # GUI + CLI smoke (15)
make test-filter FILTER=RegistrationTests
make acceptance         # full acceptance suite
make gui-smoke          # GUI build + ViewModel tests
```

Or directly:

| Suite | Tests | Covers |
|---|---|---|
| `SICLientCoreTests` | 107 | SIP, registration, sessions, media, resilience, Phase 5/6, feature matrix |
| `SICLientGUITests` | 15 | SwiftUI ViewModel flows, accessibility IDs, CLI subprocess smoke |

## Run

### CLI

**Dry run (bootstrap only):**

```bash
make dry-run
# or: swift run siclient --profile profiles/lab-volte-01.json --dry-run
```

**Register against lab P-CSCF:**

```bash
make register
# or: swift run siclient --profile profiles/lab-volte-01.json
```

**MO call with media stats, hold, and DTMF:**

```bash
make mo-call MO_DEST=sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org CALL_DURATION=5 HOLD=1 DTMF=5
```

**Emergency, SMS, call forwarding:**

```bash
swift run siclient --profile profiles/lab-volte-01.json --emergency-call
swift run siclient --profile profiles/lab-volte-01.json --send-sms tel:+15551212 "hello"
swift run siclient --profile profiles/lab-volte-01.json --set-call-forwarding tel:+15559876
swift run siclient --profile profiles/lab-volte-01.json --fetch-call-forwarding
```

### GUI (lab console)

```bash
make run-gui
# or: swift run siclient-gui
```

Load a profile path, register, place calls, hold/resume, DTMF, SMS, CFU, and emergency call from the SwiftUI window. ViewModel logic is covered by `SICLientGUITests`; controls expose `gui.*` accessibility IDs for future XCUITest.

Point `pcscf.address` / `pcscf.port` at your lab IMS or use in-process `LoopbackSIPTransport` + mock responders in tests.

## Project Layout

```
Sources/SICLientCore/
  Config/           Operator profiles, validation, hot-reload
  Diagnostics/      JSON logging, secret redaction, PCAP export
  Platform/         SIM, network, bearer, PANI, discovery
  SIP/              Parser, serializer, Digest auth, transactions
  Transport/        UDP/TCP/TLS, fallback, loopback mocks
  Security/         TLS pinning, secure memory, SA policy
  Registration/     REGISTER FSM, retry, keep-alive
  Session/          INVITE FSM, PRACK, BYE, CallService, concurrent calls
  Media/            SDP, preconditions, RTP/RTCP, codecs, DTMF
  Emergency/        Priority REGISTER + emergency INVITE
  SMS/              SIP MESSAGE (RP-DATA payload option)
  Supplementary/    XCAP call forwarding
  Handover/         eSRVCC hooks
  Bootstrap/        Application entry wiring
Sources/siclient/   CLI executable
Sources/SICLientGUI/  SwiftUI views + ClientViewModel
Sources/siclient-gui/ macOS GUI executable
Tests/SICLientCoreTests/  Core unit + integration tests
Tests/SICLientGUITests/   GUI ViewModel + CLI smoke tests
Tests/gui/          GUI smoke script
Tests/sipp/         SIPp XML scenarios + acceptance script
profiles/           Operator JSON profiles
schema/             JSON schema
docs/               Architecture, API, integration, interop runbook
```

Source files include file headers and doc comments explaining IMS concepts for newcomers — start with `CallService.swift` or `RegistrationFSM.swift`.

## Registration Flow

1. Send unprotected `REGISTER` with `Security-Client`, P-headers, empty Digest
2. Receive `401` with `WWW-Authenticate` (RAND/AUTN)
3. Run IMS-AKA via `LabSimAdapter` → RES (or AUTS on sync failure)
4. Send authenticated `REGISTER` with `Authorization`
5. Parse `200 OK` → `Service-Route`, `P-Associated-URI`, `Expires`
6. Schedule re-register at 80% of expiry; send CRLF keep-alive

## Call Flow

1. Request dedicated bearer (QCI=1) via `BearerAdapter`
2. MO: `INVITE` with SDP offer + precondition attrs, `Route: Service-Route`
3. Receive `183 Session Progress` (100rel) → send `PRACK`
4. If preconditions unmet in `200 OK`, send `UPDATE` with local QoS met
5. Receive `200 OK` → send `ACK` → call active
6. `BYE` → `200 OK` → release bearer

MT incoming INVITE waits for network `PRACK` and `UPDATE` before sending `200 OK`.

## Phase 4 — Resilience

- `CallService.handleNetworkPathChange()` — re-register after IP/RAT change
- `FallbackSIPTransport` — UDP with TCP fallback when payload exceeds `resilience.mtu_bytes`
- Registration retry on 408/503 with exponential backoff
- OPTIONS keep-alive on TCP/TLS; CRLF on UDP
- Registration loss terminates active calls (BYE)

## Phase 5 — Services

| Feature | API | Profile flag |
|---|---|---|
| Emergency IMS | `registerEmergency()`, `placeEmergencyCall()` | `services.emergency.enabled` |
| SMS over IMS | `sendSMS(to:text:)` | `services.sms.enabled` |
| Call forwarding (XCAP) | `fetchCallForwarding()`, `setCallForwarding()` | `services.supplementary.enabled` |
| eSRVCC hooks | `beginESRVCCHandover()`, `completeESRVCCHandover()` | `services.handover.esrvcc_enabled` |
| STIR-SHAK Identity | auto on INVITE | `services.handover.stir_shak_enabled` |
| EVS premium codec | SDP + `LabEVSCodecEngine` | `codecs.audio: ["EVS", ...]` |

Premium profile: `profiles/lab-volte-evs-premium.json`

## Phase 6 — Production Readiness (lab)

| Feature | Key types |
|---|---|
| AUTS resync REGISTER | `RegistrationFSM`, `DigestCredentials.auts` |
| TLS + cert pinning | `TLSTransport`, `TLSConfiguration` |
| PCO/DHCP + DNS SRV discovery | `IMSDiscovery`, `ProductionNetworkAdapter` |
| Concurrent calls (1 active + 1 held) | `SessionFSM.heldSession` |
| Keychain SIM | `KeychainSimAdapter`, `SimAdapterFactory` |
| Profile hot-reload, PCAP, key zeroization | `ProfileManager`, `PcapExporter`, `SecureMemory` |
| SMS RP-DATA, XCAP digest, eSRVCC REFER | `SMSPayloadBuilder`, `XCAPDigestAuth`, `ESRVCCCoordinator` |

See `docs/operator-interop-runbook.md` for operator lab validation.

## SIPp Conformance

See `Tests/sipp/README.md`.

```bash
chmod +x Tests/sipp/run-*.sh Tests/gui/run-gui-smoke.sh

# Full acceptance (tests + CLI + GUI + optional SIPp)
./Tests/sipp/run-acceptance.sh

# REGISTER (two terminals)
./Tests/sipp/run-uas.sh 127.0.0.1 15060
./Tests/sipp/run-register.sh 127.0.0.1:15060

# MO VoLTE with preconditions
./Tests/sipp/run-uas-volte.sh 127.0.0.1 15060
./Tests/sipp/run-mo-call.sh 127.0.0.1:15060
```

## Documentation

| Document | Purpose |
|---|---|
| [docs/user-guide.md](docs/user-guide.md) | **End-user guide** — CLI and GUI usage, workflows, troubleshooting |
| [docs/deployment-guide.md](docs/deployment-guide.md) | **Deployment guide** — build, install, configure, operate |
| `spec.md` | Functional spec, acceptance criteria, phase checklist |
| `docs/ARCHITECTURE.md` | Module map and dependency direction |
| `docs/api-reference.md` | Public `SICLientCore` + GUI API surface |
| `docs/integration-guide.md` | Host app integration for developers |
| `docs/operator-interop-runbook.md` | Operator IMS lab validation steps |
| `docs/adr/0001-swift-platform-and-sip-stack.md` | Platform and IPSec deferral ADR |

## License

Proprietary — internal IMS client development.
