# SICLient

IMS SIP Client for macOS Tahoe (Swift 6). Phase 3 adds RTP/RTCP media, lab audio codec framing, DTMF, ViLTE SDP, and hold/resume on top of Phase 2 session control.

## Requirements

- macOS 26 (Tahoe) or later
- Swift 6.2+ (Xcode 26 / Swift 6.3 toolchain)

## Build

```bash
swift build
```

## Test

```bash
swift test
```

60 unit and integration tests cover profile loading, SIP parsing, IMS headers, registration, SDP/preconditions, MO/MT call flows, RTP/RTCP media, hold/resume, resilience, performance NFRs, and loopback mock IMS.

## Run

**Dry run (bootstrap only):**

```bash
swift run siclient --profile profiles/lab-volte-01.json --dry-run
```

**Register against lab P-CSCF (requires reachable P-CSCF in profile):**

```bash
swift run siclient --profile profiles/lab-volte-01.json
```

**MO call with media stats, hold, and DTMF:**

```bash
swift run siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org \
  --call-duration 5 --hold --dtmf 5
```

Profile `media` block controls RTP transport (`udp` | `loopback`), local port, FFmpeg codec, and AVAudioEngine I/O.

**Register then originate MO call (requires registered P-CSCF + callee):**

```bash
swift run siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org
```

**Register then deregister:**

```bash
swift run siclient --profile profiles/lab-volte-01.json --deregister
```

Point `pcscf.address` / `pcscf.port` at your lab IMS or use the in-process `LoopbackSIPTransport` + `MockIMSResponder` in tests.

## Project Layout

```
Sources/SICLientCore/
  Config/           Operator profiles
  Diagnostics/      JSON logging, secret redaction
  Platform/         SIM, network, bearer, PANI adapters
  SIP/              Parser, serializer, Digest auth, client transaction
  Transport/        UDP/TCP/TLS, loopback mock
  Security/         Security association policy
  Registration/     REGISTER FSM, context, request builder
  Session/          INVITE FSM, PRACK, BYE, CallService, hold/resume
  Media/            SDP, preconditions, RTP/RTCP, codecs, DTMF
  Bootstrap/        Application entry wiring
Sources/siclient/   CLI executable
Tests/              Unit + registration/session integration tests
Tests/sipp/         SIPp XML scenarios for lab conformance
profiles/           Operator JSON profiles
schema/             JSON schema
docs/               Architecture and ADRs
```

## Registration Flow (Phase 1)

1. Send unprotected `REGISTER` with `Security-Client`, P-headers, empty Digest
2. Receive `401` with `WWW-Authenticate` (RAND/AUTN)
3. Run IMS-AKA via `LabSimAdapter` → RES
4. Send authenticated `REGISTER` with `Authorization`
5. Parse `200 OK` → `Service-Route`, `P-Associated-URI`, `Expires`
6. Schedule re-register at 80% of expiry; send CRLF keep-alive

## Call Flow (Phase 2)

1. Request dedicated bearer (QCI=1) via `BearerAdapter`
2. MO: `INVITE` with SDP offer + precondition attrs, `Route: Service-Route`
3. Receive `183 Session Progress` (100rel) → send `PRACK`
4. If preconditions unmet in `200 OK`, send `UPDATE` with local QoS met
5. Receive `200 OK` → send `ACK` → call active
6. `BYE` → `200 OK` → release bearer

MT incoming INVITE waits for network `PRACK` and `UPDATE` before sending `200 OK` (via `InviteServerTransaction`).

## Media (Phase 3)

After call establishment, `SessionFSM` optionally starts a `MediaSession` (inject `mediaTransportFactory`):

1. Parse remote RTP endpoint from negotiated SDP
2. Start RTP audio pump (20 ms frames) + RTCP sender reports
3. `CallService.hold()` / `resume()` — re-INVITE with `sendonly` / `sendrecv`
4. `CallService.mediaStats()` — packets sent/received, loss, jitter

Lab codec uses AMR-WB RTP framing without licensed compression (interop testing).

## Resilience (Phase 4)

- `CallService.handleNetworkPathChange()` — re-register after IP/RAT change
- `FallbackSIPTransport` — UDP with automatic TCP fallback when payload exceeds `resilience.mtu_bytes`
- Registration retry on 408/503 with exponential backoff
- OPTIONS keep-alive on TCP/TLS; CRLF on UDP
- Network recovery after failed re-register (profile `network_recovery_timeout_sec`)

Profile `resilience` block:

```json
{
  "resilience": {
    "mtu_bytes": 1300,
    "max_registration_retries": 3,
    "network_recovery_timeout_sec": 30
  }
}
```

Full acceptance suite:

```bash
./Tests/sipp/run-acceptance.sh
```

See `docs/integration-guide.md` and `docs/api-reference.md`.

## Phase 5 Services

| Feature | API | Profile flag |
|---|---|---|
| Emergency IMS | `registerEmergency()`, `placeEmergencyCall()` | `services.emergency.enabled` |
| SMS over IMS | `sendSMS(to:text:)` | `services.sms.enabled` |
| Call forwarding (XCAP) | `fetchCallForwarding()`, `setCallForwarding()` | `services.supplementary.enabled` |
| eSRVCC hooks | `beginESRVCCHandover()`, `completeESRVCCHandover()` | `services.handover.esrvcc_enabled` |
| STIR-SHAK Identity | auto on INVITE | `services.handover.stir_shak_enabled` |
| EVS premium codec | SDP + `LabEVSCodecEngine` | `codecs.audio: ["EVS", ...]` |

Premium profile: `profiles/lab-volte-evs-premium.json`

```bash
swift run siclient --profile profiles/lab-volte-01.json --emergency-call
swift run siclient --profile profiles/lab-volte-01.json --send-sms tel:+15551212 "hello"
swift run siclient --profile profiles/lab-volte-01.json --set-call-forwarding tel:+15559876
```

## Phase 3 Exit Gate

- [x] RTP/RTCP packet format + stream stats
- [x] Loopback RTP media during MO call
- [x] DTMF telephone-event encoding
- [x] H.264 video SDP m-line + ViLTE RTP stats stub
- [x] Hold/resume re-INVITE signaling
- [x] Production UDP RTP transport (`UDPRTPTransport`)
- [x] AMR/AMR-WB via FFmpeg subprocess (`use_ffmpeg_codec`) or lab framing stub
- [x] Lab two-way audio path (`enable_audio_io` + `AudioIODevice`)

## SIPp Conformance

See `Tests/sipp/README.md` for full details.

```bash
chmod +x Tests/sipp/run-*.sh

# REGISTER (two terminals)
./Tests/sipp/run-uas.sh 127.0.0.1 15060
./Tests/sipp/run-register.sh 127.0.0.1:15060

# MO VoLTE with preconditions
./Tests/sipp/run-uas-volte.sh 127.0.0.1 15060    # terminal 1
./Tests/sipp/run-mo-call.sh 127.0.0.1:15060      # terminal 2

# MT VoLTE (single script: UAS + caller)
./Tests/sipp/run-mt-call.sh 127.0.0.1 15061
```

## Phase 2 Exit Gate

- [x] SDP offer/answer (AMR-WB, AMR, telephone-event)
- [x] RFC 3312 preconditions in SDP + profile gating
- [x] MO/MT INVITE → 183 → PRACK → 200 → ACK → BYE
- [x] Bearer request/release on call lifecycle
- [x] `Service-Route` on MO INVITE
- [x] SIPp MO/MT scenarios pass loopback
- [x] 30 Swift tests green

IPSec-3GPP is deferred per ADR 0001; TLS profile is the default lab path. RTP media is Phase 3.

## License

Proprietary — internal IMS client development.
