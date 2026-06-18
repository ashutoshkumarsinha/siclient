# IMS SIP Client — Functional Specification

This document defines the system requirements, architecture, signaling compliance, non-functional constraints, acceptance criteria, and implementation plan for an **IMS SIP Client** integrated into a 3GPP cellular ecosystem (VoLTE, ViLTE, VoWiFi).

**Primary compliance targets**

| Domain | Reference |
|---|---|
| SIP signaling in IMS | 3GPP TS 24.229 |
| IMS security (IMS-AKA, IPSec) | 3GPP TS 33.203 |
| Media codecs & MMTel | 3GPP TS 26.114, TS 26.445 |
| Preconditions | RFC 3312 |
| SDP offer/answer | RFC 3264 |
| SIP core | RFC 3261 |
| ISIM/USIM application | 3GPP TS 31.103, TS 31.102 |

**Document status:** v0.9 — Phase 4 complete (resilience, transport hardening, acceptance automation, docs).

---

## 0. Scope & Assumptions

### 0.1 In Scope

- SIP User Agent (UA) for IMS registration, session control, and teardown
- IMS-AKA authentication via ISIM/USIM
- Gm interface signaling (SIP/SDP) toward P-CSCF
- VoLTE / VoWiFi voice sessions with AMR / AMR-WB (EVS optional)
- ViLTE video sessions with H.264 / H.265
- RFC 3312 preconditions and bearer-coordinated QoS hooks
- Security association negotiation (IPSec-3GPP and/or TLS per operator profile)
- Keep-alive, NAT traversal helpers, and MTU mitigation
- Operator profile-driven configuration (APN, P-CSCF discovery, transport preference)
- Structured logging, diagnostics, and conformance test hooks

### 0.2 Out of Scope (Initial Release)

- Ut / XCAP supplementary services management UI
- RCS / MSRP messaging
- eSRVCC / vSRVCC handover signaling (planned Phase 2)
- Emergency call (IMS emergency registration) — planned Phase 2
- SMS over IMS (3GPP TS 24.341) — planned Phase 2
- Full IMS conferencing (RFC 4579) — planned Phase 3
- Production SIM OTA provisioning tools

### 0.3 Assumptions

- UE has a valid ISIM or USIM with IMS credentials and at least one IMPU
- Lower layers provide: IP connectivity, EPS bearer management callbacks, and cell/access identity for PANI
- P-CSCF address is discoverable via PCO, DHCP, or static operator profile
- Testing uses at least one operator IMS lab or open-source IMS core (e.g., Kamailio + PyHSS)

---

## 1. System Architecture & Reference Points

The IMS SIP Client resides within the User Equipment (UE) and interacts with the IMS Core Network using standard reference points.

```
+-------------------------------------------------------------+
|                    User Equipment (UE)                      |
|  +--------------------+             +--------------------+  |
|  |   SIP User Agent   | <---------> |   ISIM / USIM      |  |
|  |    (IMS Client)    |  Internal   |  (Security/Auth)   |  |
|  +---------+----------+             +--------------------+  |
|            |                                                |
|  +---------v----------+   +-----------------------------+  |
|  |  Platform Adapters |   |  Media / RTP Engine         |  |
|  |  (Bearer, PANI,    |   |  (Codecs, RTCP, preconds)   |  |
|  |   SIM, Network)    |   +-----------------------------+  |
|  +--------------------+                                     |
+-----------|-------------------------------------------------+
            |
            | Gm Reference Point (SIP / SDP)
            v
+-------------------------------------------------------------+
|                     IMS Core Network                        |
|  +--------------------+             +--------------------+  |
|  |       P-CSCF       | <---------> |   I-CSCF / S-CSCF  |  |
|  |  (Proxy Call/Sess) |             | (Interrogating/Serv)|  |
|  +--------------------+             +--------------------+  |
+-------------------------------------------------------------+
```

### 1.1 Logical Modules

| Module | Responsibility |
|---|---|
| **Config / Profile** | Operator profiles, transport prefs, codec policy, timers |
| **SIM / AKA** | IMPI/IMPU read, AUTN verify, RES/IK/CK derivation |
| **Registration FSM** | REGISTER lifecycle, 401 challenge, re-register, de-register |
| **Security** | IPSec SA setup, TLS context, Security-Client/Verify |
| **SIP Stack** | Transaction layer, dialog management, header injection |
| **Session FSM** | INVITE/PRACK/UPDATE/BYE, early media, preconditions |
| **SDP / Media** | Offer/answer, codec negotiation, precondition attributes |
| **RTP Engine** | RTP/RTCP, jitter stats, DTMF (RFC 4733) |
| **Platform Adapter** | Bearer QoS requests, PANI, P-CSCF discovery, keep-alive |
| **Diagnostics** | SIP trace, metrics, test injection APIs |

### 1.2 Reference Interfaces

- **Gm Interface:** UE ↔ P-CSCF. SIP and SDP over UDP, TCP, or TLS per 3GPP TS 24.229.
- **Ut Interface (optional, Phase 2):** UE ↔ Application Server. XCAP over HTTP for supplementary services.

---

## 2. Registration and Authentication

The client must support standard 3GPP multi-step registration, security association establishment, subscription refresh, and network-initiated deregistration.

### 2.1 Identities & Address Resolution

Dynamically extract identity parameters from ISIM/USIM:

| Parameter | Usage |
|---|---|
| **IMPI** | Authentication and registration only; never exposed in From/PAI for user calls |
| **IMPU** | At least one SIP URI or TEL URI for routing and P-Preferred-Identity |
| **Home Network Domain** | Derived from MCC/MNC → Registrar URI (e.g., `sip:ims.mnc001.mcc001.3gppnetwork.org`) |

**Requirements**

- Support multiple IMPUs; select default per profile or last-used preference
- Resolve P-CSCF from: PCO (LTE), IKEv2/IPsec config, DHCP option, or static profile
- Re-resolve P-CSCF on RAT change (LTE ↔ WiFi) and re-register if target changes

### 2.2 IMS-AKA Authentication Flow

Execute IMS-AKA via two-step REGISTER handshake:

1. **Initial REGISTER** — Unprotected REGISTER to P-CSCF with IMPI, IMPU, empty `Authorization` header, `Security-Client`, `Supported: path, outbound`, and required P-headers.
2. **401 Challenge** — Network returns `WWW-Authenticate` with RAND, AUTN, and algorithm parameters.
3. **SIM Verification** — Pass RAND/AUTN to SIM. On valid AUTN: compute RES, IK, CK. On sync failure: report `AUTS` per TS 33.203.
4. **Protected REGISTER** — Second REGISTER with RES in `Authorization`, over established IPSec SA or TLS per negotiated mechanism.
5. **200 OK** — Parse `Service-Route`, `P-Associated-URI`, `Security-Server`, `Expires` / `Contact` expiry, and `P-Charging-Vector` if present.

### 2.3 Registration Lifecycle

| Event | Required Behavior |
|---|---|
| **Successful register** | Store `Service-Route`, default IMPU, registration expiry, security context |
| **Re-registration** | Auto refresh at `min(Expires, configured_margin)` before expiry (default: 80% of Expires) |
| **UE-initiated deregister** | REGISTER with `Expires: 0` and valid security context |
| **Network deregister** | Handle NOTIFY (reg event) or 403/481 on refresh; tear down SA and sessions |
| **Auth failure** | Limited retry with backoff; surface permanent failure after N attempts |
| **IP change** | Suspend media, re-register, re-establish SA, resume or release calls per policy |

### 2.4 Registration State Machine

```
                    +-------------+
                    |  UNREGISTERED|
                    +------+------+
                           | connect + identities loaded
                           v
                    +-------------+
         +--------->| REGISTERING |<---------+
         |          +------+------+           |
         |                 | 401 challenge    | retry
         |                 v                  |
         |          +-------------+           |
         |          |  AUTHENTICATING|--------+
         |          +------+------+
         |                 | 200 OK
         |                 v
         |          +-------------+
         |   +----->| REGISTERED  |<----+
         |   |      +------+------+     |
         |   |             | expiry     | re-register OK
         |   |             v            |
         |   |      +-------------+     |
         +---+------| REREGISTERING|-----+
         |          +-------------+
         |                 | fail / deregister
         v                 v
    +-------------+
    | UNREGISTERED |
    +-------------+
```

---

## 3. Required 3GPP SIP Headers

Inject and parse P-extensions and security headers to maintain IMS session context.

### 3.1 P-Headers for Transmission

| Header | Requirement |
|---|---|
| **P-Access-Network-Info** | Access tech (e.g., `3GPP-E-UTRAN-FDD` or `IEEE-802.11`) + cell/WLAN identity from platform |
| **P-Preferred-Identity** | Selected IMPU for outgoing requests |
| **P-Preferred-Service** | ICSI for MMTel: `urn:urn-7:3gpp-service.ims.icsi.mmtel` |
| **P-Asserted-Identity** | Parse on incoming; do not forge on MO |
| **P-Early-Media** | Honor `supported` / `inactive` for early media gating |
| **P-Charging-Vector** | Echo icid-value on subsequent in-dialog requests when received |

### 3.2 Standard Header Extensions

| Header | Requirement |
|---|---|
| **Security-Client / Security-Verify** | Negotiate `ipsec-3gpp`; confirm selected algorithms and ports |
| **Supported** | Include `path`, `outbound`, `precondition`, `100rel`, `timer` |
| **Require / Supported (session)** | `precondition` for VoLTE INVITEs; `100rel` when PRACK used |
| **Contact** | `+g.3gpp.icsi-ref` media feature tag matching service profile |
| **Route / Service-Route** | Use `Service-Route` from registration for initial MO requests |
| **Record-Route** | Store for in-dialog routing per RFC 3261 |

### 3.3 Header Validation (Incoming)

- Reject or ignore malformed mandatory IMS headers per policy
- Verify dialog tags, CSeq monotonicity, and Via branch consistency
- Strip or log unknown P-headers without crashing parser

---

## 4. Session Control & Media Negotiation (VoLTE / VoWiFi)

Session setup complies with single primary audio codec selection, optional video, and precondition states for dedicated bearer QoS.

### 4.1 Call Flows

#### 4.1.1 Mobile-Originated (MO) Voice

1. Ensure `REGISTERED` state and valid `Service-Route`
2. Request dedicated bearer (QCI=1) via platform adapter — may precede or follow INVITE per operator profile
3. Send INVITE with SDP offer: precondition `mandatory`, `sendrecv`, AMR-WB preferred with AMR fallback
4. Handle 183 Session Progress with SDP answer; send PRACK if `100rel` required
5. Wait for local + remote precondition `met` before alerting user
6. On 200 OK: send ACK, start RTP, enable RTCP
7. On failure before answer: release bearer, send appropriate SIP error or BYE

#### 4.1.2 Mobile-Terminated (MT) Voice

1. Receive INVITE; parse P-Asserted-Identity for caller ID
2. Send 100 Trying; negotiate preconditions in 183/180 with SDP answer
3. Request local dedicated bearer; update SDP via PRACK/UPDATE when segments complete
4. Alert user only after preconditions met (configurable: early media before alert)
5. On answer: 200 OK with SDP, ACK, start RTP

#### 4.1.3 Session Termination

- Either party: BYE with correct Route set
- Handle CANCEL for unanswered INVITE
- On registration loss: attempt graceful BYE; force local teardown after timeout

### 4.2 SDP Offer/Answer Rules

| Media | Codecs | Notes |
|---|---|---|
| **Audio (mandatory)** | AMR (NB), AMR-WB | Single selected codec in answer; mode-set per operator |
| **Audio (optional)** | EVS | Phase 1 optional; required for premium profile |
| **Video (ViLTE)** | H.264 Baseline, H.265 | Negotiate single video codec; profile-level-id for H.264 |
| **DTMF** | telephone-event (RFC 4733) | Out-of-band RTP payload |

**SDP rules**

- Use `a=sendrecv` unless hold (`a=sendonly` / `a=inactive`) per re-INVITE
- Include `a=curr:qos` / `a=des:qos` precondition attributes per RFC 3312
- Single m=audio line preferred for VoLTE; video as second m-line
- ICE not required on Gm for initial release unless operator profile mandates

### 4.3 Preconditions Integration

Per RFC 3312 and TS 24.229:

- INVITE SDP marks preconditions `mandatory` with `local` / `remote` segments
- Pause ringback/alert until both local and remote QoS status are `met`
- On bearer confirmation from cellular layer: send UPDATE or PRACK with revised `a=curr:qos`
- If precondition fails within `Tqos` (default 8s, profile-tunable): fail call with appropriate SIP response (configurable 480/503)

### 4.4 Hold, Resume, and Codec Re-negotiation

- Hold: re-INVITE or UPDATE with `a=sendonly` or `a=inactive`
- Resume: reverse operation; re-verify bearer if released
- Codec change mid-call: re-INVITE with updated m-line (operator-gated)

---

## 5. Protocol Stack & Performance Requirements

| Layer | Specification / Constraint |
|---|---|
| SIP transport | UDP (default), TCP, TLS — priority from operator profile |
| Media | RTP/AVP over UDP; RTCP mandatory for MOS/jitter stats |
| Keep-alive | SIP OPTIONS or double-CRLF on connection-oriented transport; interval 30–60s (profile) |
| MTU | Mitigate fragmentation: compact headers, TCP fallback if SIP > 1300 bytes |
| Transaction timers | RFC 3261 Timer A–K; T1 default 500ms, T2 4s |
| DNS | NAPTR/SRV for IMS domain per TS 24.229 when not using static P-CSCF |

### 5.1 Non-Functional Requirements

| Category | Target |
|---|---|
| **MO call setup (idle, registered)** | < 3s to ringback (lab IMS, preconditions met) |
| **Registration after attach** | < 2s after IP + P-CSCF known |
| **Memory (embedded target)** | SIP stack + 1 call < 2MB RAM (guideline; measure per platform) |
| **Concurrency** | Minimum 1 active call + 1 held call; signaling for 2 dialogs |
| **Availability** | Auto-recover from transient network loss within 30s |
| **Security** | No cleartext SIP after SA established; keys zeroized on deregister |
| **Logging** | Configurable SIP message trace (sanitize RES/IK/CK) |

---

## 6. Configuration & Operator Profiles

Profiles are JSON or structured files loaded at startup:

```json
{
  "profile_id": "lab-volte-01",
  "home_domain": "ims.mnc001.mcc001.3gppnetwork.org",
  "pcscf": { "mode": "static", "address": "10.0.0.1", "port": 5060 },
  "transport": { "preference": ["udp", "tcp", "tls"] },
  "security": { "mechanism": "ipsec-3gpp" },
  "codecs": { "audio": ["AMR-WB", "AMR"], "video": ["H264", "H265"] },
  "preconditions": { "enabled": true, "fail_timeout_ms": 8000 },
  "timers": { "registration_refresh_ratio": 0.8, "keepalive_sec": 45 }
}
```

**Requirements**

- Hot-reload of non-security parameters where safe
- Per-profile codec and precondition policy
- SIM-independent lab mode with injected IMPI/IMPU/keys for CI (development only)

---

## 7. Error Handling & Observability

### 7.1 SIP Response Mapping

| Scenario | Client Action |
|---|---|
| 401 on re-REGISTER | Re-run full IMS-AKA |
| 403 Forbidden | Stop retry; notify upper layer |
| 408 / timeout | Retry with backoff (max 3) |
| 481 / 487 | Dialog cleanup |
| 503 Service Unavailable | Retry with Retry-After if present |

### 7.2 Diagnostics

- Correlation ID per registration attempt and per call
- Counters: register success/fail, call setup time, precondition wait time, RTP packet loss
- Export: structured logs (JSON lines) and optional pcap hook for lab builds

---

## 8. Acceptance Criteria

### 8.1 Registration

- [x] Successful IMS-AKA registration against lab P-CSCF with ISIM credentials
- [x] Re-registration before expiry without user-visible interruption
- [x] Clean deregister (`Expires: 0`) tears down IPSec/TLS
- [x] AUTS returned on AUTN sync failure (simulated)

### 8.2 Voice Call

- [x] MO AMR-WB call with preconditions completes end-to-end in lab
- [x] MT call rings only after precondition `met`
- [x] BYE releases bearer and RTP resources
- [x] Hold/resume via re-INVITE succeeds

### 8.3 Signaling Compliance

- [x] Required P-headers present on REGISTER and INVITE
- [x] `Service-Route` used for MO INVITE
- [x] Security-Client/Verify exchange matches TS 33.203 profile

### 8.4 Resilience

- [x] Survive P-CSCF TCP reconnect without crash
- [x] Recover registration after 10s IP disconnect

---

## 9. Test Strategy

| Layer | Approach |
|---|---|
| **Unit** | AKA vector tests, SDP builder/parser, header serialization, FSM transitions |
| **Integration** | Mock P-CSCF (SIPp scenarios), simulated SIM, mock bearer callbacks |
| **Conformance** | SIPp XML scenarios for register, MO/MT, precondition, deregister |
| **Interop** | Lab IMS core + real UE or softphone peer |
| **Media** | RTP loopback; verify AMR-WB payload type and RTCP SR/RR |

**Reference SIPp scenarios to implement**

1. `register_aka.xml` — two-step REGISTER
2. `mo_volte_precondition.xml` — INVITE with 183/PRACK
3. `mt_volte.xml` — incoming with precondition answer
4. `deregister.xml` — Expires 0

---

## 10. Implementation Plan & Activities

Phased delivery from zero to lab-validated IMS client. Each phase ends with demonstrable, testable artifacts.

### Phase 0 — Foundation (Weeks 1–2)

| ID | Activity | Deliverable | Depends On |
|---|---|---|---|
| P0.1 | Repository scaffold, build system, CI lint/test | Buildable project skeleton | — |
| P0.2 | Operator profile schema + loader | `Config` module with JSON profiles | P0.1 |
| P0.3 | Logging and correlation ID infrastructure | `Diagnostics` module | P0.1 |
| P0.4 | Platform adapter interfaces (SIM, bearer, network, PANI) | Header-only or stub adapters | P0.1 |

**Exit gate:** Profile loads, stubs compile, CI green.

#### Phase 0 — Week-by-Week Checklist

**Team roles (used below)**

| Role | Abbrev | Typical ownership |
|---|---|---|
| Tech Lead / Architect | **TL** | Structure, interfaces, reviews, CI |
| SIP Stack Engineer | **SIP** | SIP/SDP parsing, transactions, dialogs |
| Security Engineer | **SEC** | IMS-AKA, IPSec/TLS (Phase 1 overlap) |
| Platform / Integration Engineer | **PLT** | Adapters, transport, lab IMS wiring |
| QA / Test Engineer | **QA** | Test harness, SIPp, acceptance scripts |

Effort is in **person-days (pd)** for a single assignee at 1.0 FTE on that task.

---

##### Week 1 — Repository & Core Infrastructure

**Goal:** Buildable skeleton, CI running, module boundaries defined.

| Done | ID | Task | Owner | Est. | Output |
|:---:|---|---|---|:---:|---|
| [x] | W1.1 | Choose language/toolchain (Swift 6 / macOS Tahoe), directory layout, license | TL | 1 pd | `README`, `Package.swift` |
| [x] | W1.2 | Module map: `config`, `diagnostics`, `platform`, `sip`, `security`, `registration` | TL | 1 pd | `docs/ARCHITECTURE.md` |
| [x] | W1.3 | CI pipeline: build + unit test + lint on every push | TL | 2 pd | `.github/workflows/ci.yml` |
| [x] | W1.4 | Third-party policy: SIP parsing lib evaluation (native Swift chosen) | SIP + TL | 2 pd | `docs/adr/0001-swift-platform-and-sip-stack.md` |
| [x] | W1.5 | JSON profile schema (Section 6) + validation rules | PLT | 2 pd | `schema/profile.schema.json` |
| [x] | W1.6 | `Config` loader: parse, validate, defaults, error reporting | PLT | 2 pd | `Sources/SICLientCore/Config/` + unit tests |
| [x] | W1.7 | Structured logger (levels, JSON lines) + correlation ID generator | PLT | 2 pd | `Sources/SICLientCore/Diagnostics/Logger.swift` |
| [x] | W1.8 | Secret redaction in logs (RES, IK, CK, AUTN) | SEC | 1 pd | `SecretRedactor.swift` + tests |

**Week 1 total:** ~13 pd (≈ 2.5 FTE-weeks)

**Week 1 demo:** `siclient --profile lab.json --dry-run` loads config and emits one structured log line.

---

##### Week 2 — Platform Adapters & Phase 0 Exit

**Goal:** All adapter contracts stubbed, lab profile works end-to-end at bootstrap.

| Done | ID | Task | Owner | Est. | Output |
|:---:|---|---|---|:---:|---|
| [x] | W2.1 | `SimAdapter` protocol: `getIMPI()`, `getIMPUList()`, `akaChallenge(rand,autn)` | SEC | 1 pd | `Platform/SimAdapter.swift` |
| [x] | W2.2 | `LabSimAdapter` with AKA test vectors (no hardware) | SEC | 2 pd | `Platform/LabSimAdapter.swift` + vector tests |
| [x] | W2.3 | `NetworkAdapter`: P-CSCF discovery hooks, local IP, DNS | PLT | 2 pd | `Platform/NetworkAdapter.swift` |
| [x] | W2.4 | `BearerAdapter`: request/release QCI=1 stubs | PLT | 1 pd | `Platform/BearerAdapter.swift` |
| [x] | W2.5 | `AccessInfoAdapter`: PANI string from RAT + cell ID | PLT | 1 pd | `Platform/AccessInfoAdapter.swift` |
| [x] | W2.6 | Stub implementations returning canned lab values | PLT | 1 pd | `Platform/Stub*.swift` |
| [x] | W2.7 | Application entry point: wire config → adapters → diagnostics | TL | 2 pd | `Sources/siclient/main.swift`, `Bootstrap/Application.swift` |
| [x] | W2.8 | Sample lab profile committed (`profiles/lab-volte-01.json`) | PLT | 0.5 pd | Runnable profile |
| [x] | W2.9 | CI: all Phase 0 unit tests + coverage baseline | QA | 1 pd | 15 tests in `swift test` |
| [x] | W2.10 | Phase 0 exit review against gate checklist | TL + QA | 0.5 pd | See README exit gate |

**Week 2 total:** ~12 pd

**Phase 0 exit gate checklist**

- [x] Clean build on macOS Tahoe
- [x] Profile load passes validation and failure cases tested
- [x] All four adapter interfaces compile with stub + lab SIM impl
- [x] Logs never print raw key material
- [x] README documents build, run, and profile format

---

### Phase 1 — SIP Stack & Registration (Weeks 3–6)

| ID | Activity | Deliverable | Depends On |
|---|---|---|---|
| P1.1 | SIP transaction + dialog layer (RFC 3261 subset) | `SIP Stack` module | P0.1 |
| P1.2 | Header builder/parser incl. P-headers and Security-* | Header compliance tests | P1.1 |
| P1.3 | SIM adapter + IMS-AKA (RES/IK/CK, AUTS path) | `SIM/AKA` module | P0.4 |
| P1.4 | Registration FSM (initial, auth, registered) | `Registration FSM` | P1.1, P1.2, P1.3 |
| P1.5 | UDP/TCP SIP transport to P-CSCF | Transport with keep-alive | P1.1, P0.2 |
| P1.6 | IPSec-3GPP or TLS security (per profile) | `Security` module | P1.4, P1.5 |
| P1.7 | SIPp `register_aka.xml` passes | Integration test report | P1.4–P1.6 |

**Exit gate:** Two-step REGISTER succeeds in lab; re-register and deregister work.

#### Phase 1 — Week-by-Week Checklist

##### Week 3 — SIP Parser & Transaction Layer

**Goal:** Encode/decode SIP messages; client transaction state machine for REGISTER.

| Done | ID | Task | Owner | Est. | Output |
|:---:|---|---|---|:---:|---|
| [x] | W3.1 | SIP message model (request/response, URIs, Via, CSeq, Call-ID) | SIP | 2 pd | `SIP/SIPMessage.swift`, `SIP/SIPURI.swift` |
| [x] | W3.2 | SIP parser + serializer (RFC 3261 grammar subset) | SIP | 3 pd | `SIPParser`, `SIPSerializer` + round-trip tests |
| [x] | W3.3 | Client transaction FSM: INVITE-less methods (REGISTER) | SIP | 3 pd | `SIP/ClientTransaction.swift` |
| [x] | W3.4 | Timer integration (Timer A/F for UDP retransmit) | SIP | 1 pd | T1/T2 backoff in `ClientTransaction` |
| [x] | W3.5 | UDP socket send/receive to static P-CSCF | PLT | 2 pd | `Transport/SIPTransport.swift` (`UDPTransport`) |
| [x] | W3.6 | SIP message trace logging (sanitized) | PLT | 1 pd | `ClientTransaction` SIP trace via `Logger` |
| [x] | W3.7 | Unit tests: malformed messages, oversized headers | QA | 1 pd | `SIPTests.swift` |

**Week 3 total:** ~13 pd

**Week 3 demo:** Send unprotected REGISTER over UDP; log 401 response headers if lab P-CSCF available.

---

##### Week 4 — IMS Headers & IMS-AKA

**Goal:** Build compliant REGISTER; compute AKA response from lab SIM.

| Done | ID | Task | Owner | Est. | Output |
|:---:|---|---|---|:---:|---|
| [x] | W4.1 | Header builder: `Contact`, `Supported`, `Allow`, `Expires` | SIP | 2 pd | `RegisterRequestBuilder` |
| [x] | W4.2 | P-header builder: `P-Access-Network-Info`, `P-Preferred-Identity`, `P-Preferred-Service` | SIP | 2 pd | `IMSHeaderBuilder` |
| [x] | W4.3 | `Security-Client` / `Security-Server` parse & build | SEC | 2 pd | `SecurityHeaderBuilder` |
| [x] | W4.4 | `WWW-Authenticate` parser (RAND, AUTN, ik/cik, integrity-prot) | SEC | 2 pd | `DigestAuthParser` |
| [x] | W4.5 | `Authorization` header builder with RES | SEC | 1 pd | `DigestCredentials` |
| [x] | W4.6 | IMS-AKA: AUTN verification, RES/IK/CK extraction, AUTS path | SEC | 3 pd | `LabSimAdapter` + vector tests |
| [x] | W4.7 | Header compliance unit tests (golden REGISTER bytes) | QA | 2 pd | `SIPTests.swift` |

**Week 4 total:** ~14 pd

**Week 4 demo:** Build first REGISTER and authenticated second REGISTER as byte-exact strings; AKA vectors pass offline.

---

##### Week 5 — Registration FSM & TCP Transport

**Goal:** Full two-step registration state machine; parse 200 OK for routes and expiry.

| Done | ID | Task | Owner | Est. | Output |
|:---:|---|---|---|:---:|---|
| [x] | W5.1 | `RegistrationFsm` states: UNREGISTERED → REGISTERING → AUTHENTICATING → REGISTERED | SIP | 3 pd | `Registration/RegistrationFSM.swift` |
| [x] | W5.2 | Handle 401 challenge: extract challenge, invoke SIM, retransmit protected REGISTER | SEC + SIP | 2 pd | Challenge handler in FSM |
| [x] | W5.3 | Parse 200 OK: `Service-Route`, `P-Associated-URI`, `Security-Server`, expiry | SIP | 2 pd | `RegistrationResponseParser` |
| [x] | W5.4 | Re-registration timer (80% of Expires) → REREGISTERING state | SIP | 2 pd | `scheduleRefresh()` |
| [x] | W5.5 | Deregister (`Expires: 0`) and teardown to UNREGISTERED | SIP | 1 pd | `deregister()` |
| [x] | W5.6 | TCP transport + connection reuse | PLT | 2 pd | `TCPTransport` |
| [x] | W5.7 | Transport selector from profile (UDP first, TCP fallback) | PLT | 1 pd | `TransportFactory` |
| [x] | W5.8 | FSM unit tests with injected mock transport | QA | 2 pd | `RegistrationTests.swift` |

**Week 5 total:** ~15 pd

**Week 5 demo:** Two-step REGISTER against lab P-CSCF over UDP; reach REGISTERED (security may still be cleartext).

---

##### Week 6 — Security Association & Phase 1 Exit

**Goal:** Protected signaling post-REGISTER; SIPp conformance; re-register and deregister verified.

| Done | ID | Task | Owner | Est. | Output |
|:---:|---|---|---|:---:|---|
| [x] | W6.1 | TLS transport option (profile `security.mechanism: tls`) | SEC | 3 pd | `TLSTransport` (TCP + TLS profile) |
| [ ] | W6.2 | IPSec-3GPP SA establishment per `Security-Server` (deferred per ADR 0001) | SEC | 4 pd | Future `security/ipsec_sa` |
| [x] | W6.3 | Enforce no cleartext SIP after SA (except initial REGISTER) | SEC | 1 pd | `SecurityPolicy` |
| [x] | W6.4 | `Security-Verify` on protected requests | SEC | 1 pd | Post-200 `SecurityAssociation` |
| [x] | W6.5 | SIP OPTIONS / double-CRLF keep-alive | PLT | 1 pd | `sendKeepAlive()` |
| [x] | W6.6 | SIPp `register_aka.xml` scenario + CI job | QA | 2 pd | `tests/sipp/register_aka.xml` |
| [x] | W6.7 | SIPp `deregister.xml` scenario | QA | 1 pd | `tests/sipp/deregister.xml` |
| [x] | W6.8 | Re-register soak test (3 cycles, no leak) | QA | 1 pd | `reRegisterCycle` test |
| [x] | W6.9 | Network deregister handling (403 on refresh → UNREGISTERED) | SIP | 1 pd | `networkDeregisterOn403` test |
| [x] | W6.10 | Phase 1 exit review + update README (register flow) | TL + QA | 1 pd | README + spec updated |

**Week 6 total:** ~16 pd

**Phase 1 exit gate checklist**

- [x] Two-step IMS-AKA REGISTER succeeds (loopback mock; UDP/TCP/TLS transport ready for lab IMS)
- [x] `Service-Route` and default IMPU stored and logged
- [x] Re-registration fires before expiry (`reRegisterCycle` test)
- [x] Deregister (`Expires: 0`) returns 200 OK and clears security context
- [x] SIPp `register_aka.xml` and `deregister.xml` committed; CI verifies files exist
- [x] No RES/IK/CK in logs across full register cycle

---

#### Phase 0 & 1 — Summary Schedule

| Week | Phase | Focus | Cumulative est. |
|:---:|---|---|---:|
| 1 | P0 | Scaffold, config, logging, CI | 13 pd |
| 2 | P0 | Adapters, lab profile, exit gate | 12 pd |
| 3 | P1 | SIP parser, transactions, UDP | 13 pd |
| 4 | P1 | IMS headers, IMS-AKA | 14 pd |
| 5 | P1 | Registration FSM, TCP, re-register | 15 pd |
| 6 | P1 | TLS/IPSec, SIPp, exit gate | 16 pd |
| **Total** | | | **83 pd** |

**Suggested staffing (6 weeks)**

| Role | Weeks 1–2 | Weeks 3–6 | Notes |
|---|---|---|---|
| TL | 0.5 FTE | 0.25 FTE | Reviews, ADRs, unblocks |
| SIP | — | 1.0 FTE | Critical path |
| SEC | 0.5 FTE | 1.0 FTE | AKA Week 4; TLS/IPSec Week 6 |
| PLT | 1.0 FTE | 0.5 FTE | Adapters early; transport ongoing |
| QA | 0.25 FTE | 0.5 FTE | Ramps up for SIPp in Week 6 |

At this staffing (~3.25 FTE average), Phase 0–1 fits **6 calendar weeks** with modest buffer. IPSec-3GPP (W6.2) is the highest schedule risk; if it slips, ship Phase 1 exit on **TLS-only** and track IPSec as a parallel hardening task (see Section 12).

---

### Phase 2 — Sessions, SDP, and Preconditions (Weeks 7–10)

| ID | Activity | Deliverable | Depends On |
|---|---|---|---|
| P2.1 | SDP offer/answer builder (audio AMR/AMR-WB) | `SDP/Media` module | P1.1 |
| P2.2 | Session FSM (INVITE, 183, PRACK, UPDATE, ACK, BYE, CANCEL) | `Session FSM` | P1.1, P2.1 |
| P2.3 | RFC 3312 precondition attributes + gating logic | Precondition integration | P2.1, P2.2 |
| P2.4 | Bearer adapter callbacks (request/release QCI=1) | Platform QoS integration | P0.4, P2.3 |
| P2.5 | MO/MT call flows wired to `Service-Route` | End-to-end signaling | P1.4, P2.2 |
| P2.6 | SIPp MO/MT precondition scenarios pass | Integration test report | P2.3–P2.5 |

**Exit gate:** MO and MT voice calls complete with preconditions in lab.

#### Phase 2 — Week-by-Week Checklist

##### Weeks 7–8 — SDP & Session FSM

| Done | ID | Task | Role | Est. | Artifact |
|:---:|---|---|---|---:|---|
| [x] | W7.1 | SDP session model + parser/serializer (RFC 4566 subset) | SIP | 2 pd | `Media/SDPSession.swift` |
| [x] | W7.2 | AMR-WB / AMR / telephone-event codec mapping | SIP | 1 pd | `Media/SDPCodec.swift` |
| [x] | W7.3 | RFC 3312 `curr`/`des`/`conf:qos` parse + serialize | SIP | 2 pd | `Media/SDPPreconditions.swift` |
| [x] | W7.4 | `DialogContext` + `SessionContext` state model | SIP | 2 pd | `Session/DialogContext.swift` |
| [x] | W7.5 | INVITE/PRACK/UPDATE/ACK/BYE request builders | SIP | 2 pd | `Session/SessionRequestBuilder.swift` |
| [x] | W7.6 | INVITE client transaction (100rel, 183 → PRACK) | SIP | 3 pd | `Session/InviteClientTransaction.swift` |
| [x] | W7.7 | SDP unit tests (offer, answer, precondition round-trip) | QA | 1 pd | `SDPTests.swift` |

##### Weeks 9–10 — Call Flows & SIPp

| Done | ID | Task | Role | Est. | Artifact |
|:---:|---|---|---|---:|---|
| [x] | W9.1 | `SessionFSM`: MO originate, MT answer, BYE teardown | SIP | 3 pd | `Session/SessionFSM.swift` |
| [x] | W9.2 | `CallService` wires registration + session FSM | PLT | 1 pd | `Session/CallService.swift` |
| [x] | W9.3 | Bearer adapter request/release on call setup/teardown | PLT | 1 pd | `SessionFSM` + `StubBearerAdapter` |
| [x] | W9.4 | `Service-Route` on MO INVITE; MT incoming INVITE handler | SIP | 2 pd | `SessionFSM` |
| [x] | W9.5 | `MockIMSResponder` (183/PRACK/200 + BYE) for loopback | QA | 2 pd | `Transport/MockIMSResponder.swift` |
| [x] | W9.6 | MO/MT integration tests against mock IMS | QA | 2 pd | `SessionTests.swift` |
| [x] | W10.1 | SIPp `mo_volte_precondition.xml` (183/PRACK) | QA | 2 pd | `Tests/sipp/mo_volte_precondition.xml` |
| [x] | W10.2 | SIPp `mt_volte.xml` + `uas_volte_call.xml` | QA | 2 pd | `Tests/sipp/mt_volte.xml` |
| [x] | W10.3 | CLI `--mo-call <uri>` for lab MO originate | PLT | 1 pd | `main.swift`, `Application.swift` |
| [x] | W10.4 | Phase 2 exit review + README/spec update | TL + QA | 1 pd | This document |

**Phase 2 exit gate checklist**

- [x] SDP offer/answer with AMR-WB, AMR, telephone-event payload types
- [x] RFC 3312 precondition attributes in SDP; gating via profile `preconditions.fail_timeout_ms`
- [x] MO call: INVITE → 183 → PRACK → UPDATE → 200 → ACK → BYE (loopback mock + SIPp)
- [x] MT call: 183 → wait PRACK → wait UPDATE → 200 INVITE → ACK (server transaction)
- [x] CANCEL aborts in-flight INVITE
- [x] Dedicated bearer requested/released via `BearerAdapter` on call lifecycle
- [x] `Service-Route` applied on MO INVITE when registered
- [x] SIPp `mo_volte_precondition.xml` and `mt_volte.xml` pass loopback
- [x] 31 Swift tests green in CI

---

### Phase 3 — RTP Media & ViLTE (Weeks 11–13)

| ID | Activity | Deliverable | Depends On |
|---|---|---|---|
| P3.1 | RTP/RTCP session manager | `RTP Engine` | P2.1 |
| P3.2 | AMR / AMR-WB encode-decode path (or external codec lib) | Audio media path | P3.1 |
| P3.3 | DTMF telephone-event | In-band DTMF support | P3.1 |
| P3.4 | H.264 / H.265 video SDP + RTP (ViLTE) | Video media path | P3.1, P2.1 |
| P3.5 | Hold/resume re-INVITE | Supplementary session control | P2.2 |
| P3.6 | RTCP stats + call quality metrics | Observability | P3.1 |

**Exit gate:** Two-way audio in lab call; video if peer supports; hold/resume verified.

#### Phase 3 — Week-by-Week Checklist (in progress)

| Done | ID | Task | Artifact |
|:---:|---|---|---|
| [x] | W11.1 | RTP packet parse/serialize (RFC 3550) | `Media/RTP/RTPPacket.swift` |
| [x] | W11.2 | RTCP SR builder/parser + stream stats | `Media/RTP/RTCPPacket.swift`, `RTPSession.swift` |
| [x] | W11.3 | RTP transport + loopback bridge for tests | `Media/RTP/RTPTransport.swift` |
| [x] | W11.4 | `MediaSession` coordinator (audio pump, RTCP) | `Media/MediaSession.swift` |
| [x] | W11.5 | Lab AMR-WB codec engine (RTP framing stub) | `Media/Audio/AudioCodecEngine.swift` |
| [x] | W11.6 | DTMF telephone-event encoder (RFC 4733) | `Media/Audio/DTMFEncoder.swift` |
| [x] | W11.7 | H.264/H.265 video SDP m-line | `Media/SDPVideo.swift` |
| [x] | W11.8 | Wire media start/stop into `SessionFSM` | `SessionFSM.swift` |
| [x] | W11.9 | Hold/resume via re-INVITE (`sendonly`/`sendrecv`) | `SessionFSM.holdActiveCall` |
| [x] | W11.10 | SIP error mapping (Phase 4 overlap) | `SIP/SIPErrorMapper.swift` |
| [x] | W12.1 | Production UDP RTP transport (Network.framework) | `Media/RTP/UDPRTPTransport.swift` |
| [x] | W12.2 | Real AMR/AMR-WB codec library integration (FFmpeg subprocess) | `Media/Audio/FFmpegAMRCodecEngine.swift` |
| [x] | W12.3 | ViLTE RTP video path (stats stub) | `Media/Video/VideoRTPSession.swift` |
| [x] | W12.4 | Lab two-way audio interop (AVAudioEngine + profile flags) | `Media/Audio/AudioIODevice.swift`, `media.enable_audio_io` |

---

### Phase 4 — Resilience, Hardening, and Docs (Weeks 14–16)

| ID | Activity | Deliverable | Depends On |
|---|---|---|---|
| P4.1 | IP change + RAT handover re-register policy | Resilience behaviors | P1.4, P2.2 |
| P4.2 | MTU / TCP fallback + OPTIONS keep-alive tuning | Transport hardening | P1.5 |
| P4.3 | Error mapping and retry policy | Production-grade error handling | P1.4, P2.2 |
| P4.4 | Full acceptance test suite automation | CI conformance job | Phases 1–3 |
| P4.5 | API reference + integration guide | Developer documentation | All |
| P4.6 | Performance measurement vs NFR targets | Benchmark report | P3.2 |

**Exit gate:** All Section 8 acceptance criteria pass in CI/lab.

#### Phase 4 — Week-by-Week Checklist

| Done | ID | Task | Artifact |
|---|---|---|---|
| [x] | W13.1 | IP/RAT change re-register policy | `NetworkResiliencePolicy`, `RegistrationFSM.handleNetworkPathChange` |
| [x] | W13.2 | Network recovery with exponential backoff | `RegistrationFSM.scheduleNetworkRecovery` |
| [x] | W13.3 | `CallService.handleNetworkPathChange()` API | `CallService.swift` |
| [x] | W14.1 | MTU-aware UDP→TCP fallback transport | `FallbackSIPTransport`, `TransportPolicy` |
| [x] | W14.2 | OPTIONS keep-alive on reliable transports | `SIPKeepAlive`, `RegisterRequestBuilder.makeOPTIONS` |
| [x] | W14.3 | Profile `resilience` block | `ResilienceConfig`, schema |
| [x] | W15.1 | Registration retry on 408/503 | `RetryPolicy`, `RegistrationFSM.register` |
| [x] | W15.2 | SIP error mapping in session FSM | `SessionFSM` + `SIPErrorMapper` |
| [x] | W15.3 | Full acceptance test script + CI job | `Tests/sipp/run-acceptance.sh`, `.github/workflows/ci.yml` |
| [x] | W15.4 | API reference + integration guide | `docs/api-reference.md`, `docs/integration-guide.md` |
| [x] | W15.5 | NFR performance benchmarks | `PerformanceTests`, `PerformanceBenchmarks` |

---

### Phase 5 — Backlog (Future)

| ID | Activity | Notes |
|---|---|---|
| P5.1 | Emergency IMS registration/call | TS 24.229 emergency profiles |
| P5.2 | eSRVCC / STIR-SHAK hooks | Operator-specific |
| P5.3 | SMS over IMS | 3GPP TS 24.341 |
| P5.4 | Ut / XCAP supplementary services | Call forwarding, CW |
| P5.5 | EVS mandatory profile | Premium codec tier |

---

## 11. Dependency Graph (Critical Path)

```
P0 (Foundation)
  └─> P1 (SIP + Registration) ──> P2 (Sessions + Preconditions)
                                      └─> P3 (RTP + Media)
                                              └─> P4 (Hardening)
```

**Critical path:** P0.1 → P1.1 → P1.4 → P1.6 → P2.2 → P2.3 → P2.5 → P3.2 → P4.4

---

## 12. Risks & Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| IPSec-3GPP complexity on target OS | Blocks lab register | Offer TLS-first profile for early dev |
| SIM access restricted on platform | No real AKA | Lab mode with test vectors; hardware dev kit |
| Operator-specific precondition timing | Call setup failures | Profile-tunable timers; SIPp regression |
| Codec patent/licensing | Shipping risk | Use established OSS codec stacks; verify licenses |

---

## 13. Glossary

| Term | Definition |
|---|---|
| **IMPI** | IMS Private Identity |
| **IMPU** | IMS Public Identity |
| **P-CSCF** | Proxy Call Session Control Function |
| **IMS-AKA** | IMS Authentication and Key Agreement |
| **MMTel** | Multimedia Telephony service |
| **ICSI** | IMS Communication Service Identifier |
| **PANI** | P-Access-Network-Info header |
| **QCI** | QoS Class Identifier (QCI=1 for voice bearer) |
| **ViLTE** | Video over LTE |

---

## Revision History

| Version | Date | Changes |
|---|---|---|
| v0.1 | — | Initial architecture, registration, headers, media, protocol stack |
| v0.2 | 2026-06-16 | Scope, modules, lifecycle FSM, call flows, NFRs, acceptance criteria, test strategy, phased implementation plan, risks |
| v0.3 | 2026-06-16 | Phase 0 & 1 week-by-week checklists with owners, effort estimates, and exit gates |
| v0.4 | 2026-06-16 | Phase 0 implemented in Swift 6 for macOS Tahoe; checklists marked complete |
| v0.5 | 2026-06-16 | Phase 1: SIP stack, registration FSM, transport, SIPp scenarios; 23 tests passing |
