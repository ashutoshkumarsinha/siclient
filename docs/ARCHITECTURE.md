# Architecture

SICLient is a modular IMS SIP User Agent targeting macOS Tahoe.

## Module Map

| Module | Package Target | Phase | Responsibility |
|---|---|---|---|
| **Config** | `SICLientCore/Config` | 0 | Operator profile models, JSON load, validation, hot-reload |
| **Diagnostics** | `SICLientCore/Diagnostics` | 0 | Structured JSON logging, correlation IDs, secret redaction, PCAP |
| **Platform** | `SICLientCore/Platform` | 0–6 | SIM, network, bearer, PANI adapters; PCO/DHCP/SRV discovery |
| **Bootstrap** | `SICLientCore/Bootstrap` | 0 | Wire config → adapters → diagnostics |
| **SIP** | `SICLientCore/SIP` | 1 | Parser, transactions, dialogs, headers, error mapping |
| **Security** | `SICLientCore/Security` | 1–6 | IMS-AKA runtime, TLS pinning, secure memory, IPSec policy |
| **Registration** | `SICLientCore/Registration` | 1–6 | REGISTER FSM, AUTS resync, retry, keep-alive |
| **Session** | `SICLientCore/Session` | 2–6 | INVITE, PRACK, UPDATE, ACK, BYE, hold, concurrent calls |
| **Media** | `SICLientCore/Media` | 2–3 | SDP, preconditions, RTP/RTCP, codecs, DTMF |
| **Emergency** | `SICLientCore/Emergency` | 5 | Priority REGISTER + emergency INVITE |
| **SMS** | `SICLientCore/SMS` | 5–6 | SIP MESSAGE, optional 3GPP RP-DATA payload |
| **Supplementary** | `SICLientCore/Supplementary` | 5–6 | XCAP call forwarding, HTTP digest auth |
| **Handover** | `SICLientCore/Handover` | 5–6 | eSRVCC event hooks and REFER |
| **GUI** | `SICLientGUI` | — | SwiftUI lab console (`ClientViewModel`, `ContentView`) |

## Dependency Direction

```
siclient (CLI) ──┐
siclient-gui ────┼──> SICLientGUI ──> SICLientCore
                 │
                 └──> SICLientCore
                        ├── Bootstrap → Config, Diagnostics, Platform
                        ├── Registration (P1) → SIP, Security, Platform, Config
                        ├── Session (P2–6) → SIP, Platform, Media, Registration
                        ├── Emergency / SMS / Supplementary / Handover (P5–6)
                        └── Media (P3) → Platform
                                ├── RTP/RTCP engine
                                ├── Audio (AMR-WB lab codec, DTMF, EVS stub)
                                └── SDP (audio + video)
```

## Media Path

```
SessionFSM (call established)
    └── MediaSession
            ├── RTPSession (seq/timestamp/SSRC, stats)
            ├── RTPTransport (loopback in tests; UDP for lab)
            ├── AudioCodecEngine (LabAMRCodecEngine / FFmpeg optional)
            └── RTCP SR every 5s
```

Hold/resume uses re-INVITE with `a=sendonly` / `a=sendrecv` and pauses the audio pump via `MediaSession.setDirection`.

## Platform Adapters

| Protocol | Production (future) | Current |
|---|---|---|
| `SimAdapter` | Secure Enclave / PCSC | `LabSimAdapter`, `KeychainSimAdapter` |
| `NetworkAdapter` | `NWPathMonitor`, DNS NAPTR/SRV | `StubNetworkAdapter`, `ProductionNetworkAdapter` |
| `BearerAdapter` | Network Extension QoS hooks | `StubBearerAdapter` |
| `AccessInfoAdapter` | CoreWLAN / cell info APIs | `StubAccessInfoAdapter` |

## Test Architecture

| Layer | Location | Count |
|---|---|---|
| Core unit + integration | `Tests/SICLientCoreTests/` | 107 |
| GUI ViewModel + CLI smoke | `Tests/SICLientGUITests/` | 15 |
| SIPp signaling conformance | `Tests/sipp/` | 8 XML scenarios |
| Acceptance orchestration | `Tests/sipp/run-acceptance.sh`, `Tests/gui/run-gui-smoke.sh` | — |

Loopback transports (`LoopbackSIPTransport`, `MockPCSCFResponder`, `MockIMSResponder`) keep CI headless and fast.

## macOS Tahoe Notes

- Minimum deployment: macOS 26
- Networking: `Network.framework` for SIP/TLS; UDP RTP via `UDPRTPTransport`
- No ISIM hardware on Mac — lab profiles, `LabSimAdapter`, and Keychain credentials are the supported dev path
- SwiftUI GUI is a lab tool; production hosts embed `SICLientCore` directly

## Code Documentation

Every Swift source file includes a file header and doc comments explaining IMS terminology for newcomers. Start with `CallService.swift`, `RegistrationFSM.swift`, or `ClientViewModel.swift`.
