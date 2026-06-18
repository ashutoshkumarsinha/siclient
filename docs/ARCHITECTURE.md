# Architecture

SICLient is a modular IMS SIP User Agent targeting macOS Tahoe.

## Module Map

| Module | Package Target | Phase | Responsibility |
|---|---|---|---|
| **Config** | `SICLientCore/Config` | 0 | Operator profile models, JSON load, validation |
| **Diagnostics** | `SICLientCore/Diagnostics` | 0 | Structured JSON logging, correlation IDs, secret redaction |
| **Platform** | `SICLientCore/Platform` | 0 | SIM, network, bearer, PANI adapter protocols + stubs |
| **Bootstrap** | `SICLientCore/Bootstrap` | 0 | Wire config → adapters → diagnostics |
| **SIP** | `SICLientCore/SIP` | 1 | Parser, transactions, dialogs, headers, error mapping |
| **Security** | `SICLientCore/Security` | 1 | IMS-AKA runtime, TLS, IPSec-3GPP policy |
| **Registration** | `SICLientCore/Registration` | 1 | REGISTER FSM, re-register, deregister |
| **Session** | `SICLientCore/Session` | 2 | INVITE, PRACK, UPDATE, ACK, BYE, hold/resume |
| **Media** | `SICLientCore/Media` | 2–3 | SDP, preconditions, RTP/RTCP, codecs, DTMF |

## Dependency Direction

```
siclient (CLI)
    └── SICLientCore
            ├── Bootstrap → Config, Diagnostics, Platform
            ├── Registration (P1) → SIP, Security, Platform, Config
            ├── Session (P2–3) → SIP, Platform, Media, Registration
            └── Media (P3) → Platform
                    ├── RTP/RTCP engine
                    ├── Audio (AMR-WB lab codec, DTMF)
                    └── SDP (audio + video)
```

## Media Path (Phase 3)

```
SessionFSM (call established)
    └── MediaSession
            ├── RTPSession (seq/timestamp/SSRC, stats)
            ├── RTPTransport (loopback in tests; UDP TBD for lab)
            ├── AudioCodecEngine (LabAMRCodecEngine)
            └── RTCP SR every 5s
```

Hold/resume uses re-INVITE with `a=sendonly` / `a=sendrecv` and pauses the audio pump via `MediaSession.setDirection`.

## Platform Adapters

| Protocol | Production (future) | Current |
|---|---|---|
| `SimAdapter` | Secure Enclave / PCSC | `LabSimAdapter` |
| `NetworkAdapter` | `NWPathMonitor`, DNS | `StubNetworkAdapter` |
| `BearerAdapter` | Network Extension QoS hooks | `StubBearerAdapter` |
| `AccessInfoAdapter` | CoreWLAN / cell info APIs | `StubAccessInfoAdapter` |

## macOS Tahoe Notes

- Minimum deployment: macOS 26
- Networking: `Network.framework` for SIP transport; production RTP UDP pending
- No ISIM hardware on Mac — lab profiles and `LabSimAdapter` are the supported dev path
