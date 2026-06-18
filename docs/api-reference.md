# SICLient API Reference

Public surface of `SICLientCore` and `SICLientGUI` for IMS registration, session control, media, and lab GUI.

## Bootstrap

| Type | Description |
|---|---|
| `Application` | CLI-oriented bootstrap: load profile, register, optional MO call / SMS / XCAP |
| `ApplicationOptions` | Profile path, dry-run, deregister, MO call, emergency, SMS, XCAP flags |
| `ProfileLoader` | Load and validate operator JSON profiles |
| `ProfileManager` | Hot-reload profile JSON at runtime |
| `PlatformContext` | Aggregates platform adapters; `stubbed(profile:)` for lab |

## Registration

| Type | Description |
|---|---|
| `RegistrationFSM` | REGISTER / re-REGISTER / deregister state machine; AUTS resync on sync failure |
| `RegistrationState` | `unregistered`, `registering`, `authenticating`, `registered`, `reregistering` |
| `RegistrationContext` | `Service-Route`, IMPUs, expiry, security association |
| `CallService.register()` | Start or refresh registration |
| `CallService.deregister()` | `Expires: 0` teardown |
| `CallService.handleNetworkPathChange()` | Re-register after IP/RAT change |
| `DigestCredentials.auts` | AUTS parameter for resynchronization REGISTER |
| `IMSChallengeDecoder` | Parse RAND/AUTN from P-CSCF 401 challenge |

## Session Control

| Type | Description |
|---|---|
| `SessionFSM` | INVITE, PRACK, UPDATE, re-INVITE, BYE, CANCEL; concurrent active + held calls |
| `CallService.placeCall(to:)` | Originate MO call (requires registered) |
| `CallService.hangUp()` | Terminate active call |
| `CallService.hold()` / `resume()` | Media hold via re-INVITE |
| `CallService.cancelCall()` | CANCEL pending INVITE |
| `CallService.sendDTMF(_:)` | RFC 4733 telephone-event |
| `CallService.mediaStats()` | RTP packets sent/received, loss, jitter |
| `CallService.activeSession()` / `heldSession()` | Query concurrent call dialogs |

## Transport

| Type | Description |
|---|---|
| `SIPTransport` | `connect`, `send`, `receive`, `close` |
| `UDPTransport` / `TCPTransport` / `TLSTransport` | Network.framework transports |
| `TLSConfiguration` / `TLSTrustEvaluator` | Certificate pinning for production TLS |
| `FallbackSIPTransport` | UDP primary with TCP fallback (MTU / failure) |
| `LoopbackSIPTransport` | In-process mock for tests |
| `TransportFactory.make(endpoint:profile:)` | Profile-aware transport selection |
| `TransportPolicy` | MTU threshold and fallback protocol selection |
| `RecordingSIPTransport` | Wrap transport to capture SIP for PCAP export |

## Platform & Discovery

| Type | Description |
|---|---|
| `SimAdapter` / `LabSimAdapter` / `KeychainSimAdapter` | IMPI/IMPU and IMS-AKA |
| `SimAdapterFactory` | Select lab vs Keychain SIM from profile/env |
| `NetworkAdapter` / `ProductionNetworkAdapter` | P-CSCF discovery, local IP |
| `IMSDiscovery` | DNS NAPTR/SRV and PCO/DHCP P-CSCF resolution |
| `MutableStubNetworkAdapter` | Simulated IP/RAT changes in tests |

## Media

| Type | Description |
|---|---|
| `MediaSession` | RTP audio pump + RTCP |
| `MediaBootstrap` | RTP transport and codec factory from profile |
| `UDPRTPTransport` / `LoopbackRTPTransport` | RTP datagram paths |
| `LabAMRCodecEngine` / `FFmpegAMRCodecEngine` | AMR-WB framing / FFmpeg subprocess |
| `LabEVSCodecEngine` | EVS RTP framing stub for premium profiles |
| `AudioIODevice` | AVAudioEngine capture/playback |
| `VideoRTPSession` | ViLTE RTP stats stub |
| `DTMFEncoder` | RFC 4733 telephone-event payloads |

## Phase 5 Services

| Type | Description |
|---|---|
| `EmergencyService` | Emergency REGISTER + INVITE with Priority headers |
| `SMSService` | SIP MESSAGE for SMS over IMS |
| `SMSPayloadBuilder` | Optional 3GPP RP-DATA binary payload |
| `SupplementaryServicesClient` | XCAP GET/PUT for call forwarding |
| `XCAPDigestAuth` | HTTP Digest for XCAP requests |
| `ESRVCCCoordinator` / `HandoverAdapter` | eSRVCC handover event hooks and REFER |
| `ServicesConfig` | Profile block for emergency/SMS/XCAP/handover |

## Resilience & Diagnostics

| Type | Description |
|---|---|
| `SIPErrorMapper` | Map SIP status codes to client actions |
| `RetryPolicy` | Registration retry decisions and backoff |
| `NetworkResiliencePolicy` | IP/path change detection, recovery timing |
| `SIPKeepAlive` | CRLF vs OPTIONS keep-alive selection |
| `PerformanceMetrics` / `PerformanceBenchmarks` | NFR timing helpers |
| `Logger` | JSON structured logs with secret redaction |
| `SecretRedactor` | Strip keys/res/autn from log lines |
| `PcapExporter` | Export captured SIP messages to PCAP |
| `SecureMemory` | Zeroize sensitive buffers after AKA |

## Configuration

| Type | Description |
|---|---|
| `OperatorProfile` | Full operator JSON model |
| `ResilienceConfig` | `mtu_bytes`, `max_registration_retries`, recovery timeout |
| `MediaConfig` | RTP transport mode, ports, audio I/O, FFmpeg |
| `ProfileValidator` | Schema validation rules |

## GUI (`SICLientGUI`)

| Type | Description |
|---|---|
| `ClientViewModel` | `@MainActor` state machine for register/call/SMS/emergency/CFU |
| `ClientConnectionState` | `idle`, `bootstrapping`, `registered`, `inCall`, `error` |
| `ContentView` | SwiftUI form with profile, voice, SMS, supplementary, emergency sections |
| `AccessibilityID` | Stable `gui.*` identifiers for UI automation |

Launch: `swift run siclient-gui`

## Mock Lab Components

| Type | Description |
|---|---|
| `MockPCSCFResponder` | Two-step REGISTER (401 → 200); AUTS test vectors |
| `MockIMSResponder` | MO VoLTE with preconditions, re-INVITE, MESSAGE, XCAP |
| `LabSimAdapter` | Injected IMS-AKA test vectors |
| `MutableStubNetworkAdapter` | Simulated IP/RAT changes in tests |

## Test Entry Points

```bash
swift test                              # 122 tests
swift test --filter SICLientGUITests    # GUI ViewModel + CLI smoke
./Tests/sipp/run-acceptance.sh          # Full acceptance suite
./Tests/gui/run-gui-smoke.sh            # GUI build smoke
```
