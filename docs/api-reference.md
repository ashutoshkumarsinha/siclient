# SICLient API Reference

Public surface of `SICLientCore` for IMS registration, session control, and media.

## Bootstrap

| Type | Description |
|---|---|
| `Application` | CLI-oriented bootstrap: load profile, register, optional MO call |
| `ApplicationOptions` | Profile path, dry-run, deregister, MO call flags |
| `ProfileLoader` | Load and validate operator JSON profiles |
| `PlatformContext` | Aggregates platform adapters; `stubbed(profile:)` for lab |

## Registration

| Type | Description |
|---|---|
| `RegistrationFSM` | REGISTER / re-REGISTER / deregister state machine |
| `RegistrationState` | `unregistered`, `registering`, `authenticating`, `registered`, `reregistering` |
| `RegistrationContext` | `Service-Route`, IMPUs, expiry, security association |
| `CallService.register()` | Start or refresh registration |
| `CallService.deregister()` | `Expires: 0` teardown |
| `CallService.handleNetworkPathChange()` | Re-register after IP/RAT change |

## Session Control

| Type | Description |
|---|---|
| `SessionFSM` | INVITE, PRACK, UPDATE, re-INVITE, BYE, CANCEL |
| `CallService.placeCall(to:)` | Originate MO call (requires registered) |
| `CallService.hangUp()` | Terminate active call |
| `CallService.hold()` / `resume()` | Media hold via re-INVITE |
| `CallService.cancelCall()` | CANCEL pending INVITE |
| `CallService.sendDTMF(_:)` | RFC 4733 telephone-event |
| `CallService.mediaStats()` | RTP packets sent/received, loss, jitter |

## Transport

| Type | Description |
|---|---|
| `SIPTransport` | `connect`, `send`, `receive`, `close` |
| `UDPTransport` / `TCPTransport` / `TLSTransport` | Network.framework transports |
| `FallbackSIPTransport` | UDP primary with TCP fallback (MTU / failure) |
| `LoopbackSIPTransport` | In-process mock for tests |
| `TransportFactory.make(endpoint:profile:)` | Profile-aware transport selection |
| `TransportPolicy` | MTU threshold and fallback protocol selection |

## Media

| Type | Description |
|---|---|
| `MediaSession` | RTP audio pump + RTCP |
| `MediaBootstrap` | RTP transport and codec factory from profile |
| `UDPRTPTransport` / `LoopbackRTPTransport` | RTP datagram paths |
| `LabAMRCodecEngine` / `FFmpegAMRCodecEngine` | AMR-WB framing / FFmpeg subprocess |
| `AudioIODevice` | AVAudioEngine capture/playback |
| `VideoRTPSession` | ViLTE RTP stats stub |

## Resilience & Diagnostics

| Type | Description |
|---|---|
| `SIPErrorMapper` | Map SIP status codes to client actions |
| `RetryPolicy` | Registration retry decisions and backoff |
| `NetworkResiliencePolicy` | IP/path change detection, recovery timing |
| `SIPKeepAlive` | CRLF vs OPTIONS keep-alive selection |
| `PerformanceMetrics` / `PerformanceBenchmarks` | NFR timing helpers |
| `Logger` | JSON structured logs with secret redaction |

## Configuration

| Type | Description |
|---|---|
| `OperatorProfile` | Full operator JSON model |
| `ResilienceConfig` | `mtu_bytes`, `max_registration_retries`, recovery timeout |
| `MediaConfig` | RTP transport mode, ports, audio I/O, FFmpeg |
| `ProfileValidator` | Schema validation rules |

## Mock Lab Components

| Type | Description |
|---|---|
| `MockPCSCFResponder` | Two-step REGISTER (401 → 200) |
| `MockIMSResponder` | MO VoLTE with preconditions, re-INVITE |
| `LabSimAdapter` | Injected IMS-AKA test vectors |
| `MutableStubNetworkAdapter` | Simulated IP/RAT changes in tests |
