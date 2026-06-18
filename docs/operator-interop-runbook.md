# Operator IMS Interop Runbook

This runbook describes how to validate SICLient against a lab IMS core (P6.8).

**Related:** [user-guide.md](user-guide.md) · [deployment-guide.md](deployment-guide.md)

## Prerequisites

- macOS 26+ with Swift 6.2+
- Reachable P-CSCF (static profile, PCO/DHCP list, or DNS SRV)
- Lab ISIM credentials in profile `lab_sim` block, or Keychain via `SICLIENT_KEYCHAIN_ACCOUNT`
- Optional: SIPp for signaling regression

## Lab topology

```
UE (siclient / siclient-gui) --Gm--> P-CSCF --Cx/Dx--> HSS (PyHSS)
                                        |
                                        +--> S-CSCF (Kamailio)
```

## Step 1 — Profile

Copy `profiles/lab-volte-01.json` and set:

- `pcscf.address` / `pcscf.port` to your P-CSCF
- `lab_sim.impi`, `impus`, and `aka_vectors` from your HSS
- `security.tls.allow_insecure_lab`: `true` for self-signed lab certs; `false` with `pinned_cert_sha256` for production TLS

For PCO discovery:

```json
"pcscf": {
  "mode": "pco",
  "pco_addresses": ["10.0.0.1:5060"]
}
```

Or set `SICLIENT_PCO_PCSCF=10.0.0.1:5060`.

## Step 2 — Register

**CLI:**

```bash
swift run siclient --profile profiles/lab-volte-01.json
```

**GUI:**

```bash
swift run siclient-gui
```

Load your profile path, click **Register**. Expected log: `Registered` / `IMS registration complete`.

## Step 3 — MO voice call

**CLI:**

```bash
swift run siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:peer@your-lab-domain --call-duration 30
```

**GUI:** enter destination URI, click **Call**.

Verify on IMS: INVITE with preconditions, 183/PRACK/UPDATE, 200 OK, RTP on negotiated port.

## Step 4 — Resilience

1. Toggle network path (WiFi ↔ tethering) while registered.
2. Confirm re-register within `resilience.network_recovery_timeout_sec`.
3. During active call, force registration loss — calls should receive BYE (P6.5).

## Step 5 — Acceptance suite

```bash
swift test                    # 122 unit + integration tests
./Tests/gui/run-gui-smoke.sh  # GUI build + ViewModel tests
./Tests/sipp/run-acceptance.sh  # full suite incl. optional SIPp
```

## Step 6 — Production TLS

Set in profile:

```json
"security": {
  "mechanism": "tls",
  "tls": {
    "allow_insecure_lab": false,
    "pinned_cert_sha256": ["abc123..."]
  }
}
```

Obtain fingerprint:

```bash
openssl s_client -connect pcscf.example:5061 </dev/null 2>/dev/null \
  | openssl x509 -outform DER | openssl dgst -sha256
```

## Step 7 — Capture signaling (optional)

Wrap transport with `RecordingSIPTransport` and export via `PcapExporter` for Wireshark analysis.

## Known gaps (post Phase 6)

| Item | Status |
|---|---|
| IPSec-3GPP SA | Deferred — use TLS-first (ADR 0001) |
| Hardware ISIM / PCSC | Keychain adapter only on macOS |
| Licensed AMR/EVS | Integrator supplies codec stack |
| ViLTE camera path | SDP + stats stub |
| XCUITest GUI automation | ViewModel tests in CI; full UI tests need Xcode |

## Troubleshooting

| Symptom | Check |
|---|---|
| 401 loop | AKA vectors match HSS; AUTS resync if SQN drift |
| TLS handshake fail | Pin fingerprint, SNI, port 5061 |
| No RTP | `media.local_rtp_port`, firewall, codec offer |
| 403 on register | IMPU not provisioned in HSS |
| GUI buttons disabled | Load profile first; check `ClientConnectionState` in log pane |

## Related docs

- `docs/integration-guide.md` — host integration
- `docs/user-guide.md` — CLI/GUI end-user guide
- `docs/deployment-guide.md` — build, install, configure
- `docs/api-reference.md` — public API
- `spec.md` §8 — lab vs production acceptance criteria
