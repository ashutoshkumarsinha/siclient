# SICLient User Guide

This guide explains how to use **siclient** (command line) and **siclient-gui** (SwiftUI lab console) to register on an IMS network and place VoLTE calls, send SMS, and manage supplementary services.

For installation and server-side setup, see [deployment-guide.md](deployment-guide.md).

---

## 1. What SICLient does

SICLient is an **IMS SIP client** for macOS. It can:

- **Register** your device on an operator IMS core (VoLTE/VoWiFi Gm interface)
- **Place and receive voice calls** with AMR-WB/AMR codecs and QoS preconditions
- **Hold, resume, and send DTMF** during active calls
- **Send SMS** over IMS (SIP MESSAGE)
- **Manage call forwarding** via XCAP
- **Place emergency calls** with Priority headers (lab routing)

You need an **operator profile** (JSON file) with your network settings and credentials. Sample profiles ship in `profiles/`.

---

## 2. Before you start

### What you need

1. macOS 26+ with SICLient installed ([deployment guide](deployment-guide.md))
2. An operator profile pointing at your P-CSCF
3. Network access to the IMS lab or operator core
4. Valid IMPI/IMPU and AKA credentials (in profile or Keychain)

### Quick health check

```bash
siclient --profile profiles/lab-volte-01.json --dry-run
```

You should see JSON log lines including `"SICLient bootstrap complete"`. No SIP signaling is sent in dry-run mode.

### Understanding logs

All output is **JSON**, one object per line:

```json
{"level":"info","message":"SICLient bootstrap complete","fields":{"profile_id":"lab-volte-01","pcscf":"10.0.0.1:5060"},...}
```

| Field | Meaning |
|---|---|
| `message` | What happened |
| `fields.profile_id` | Which operator profile is loaded |
| `fields.pcscf` | P-CSCF address used for SIP |
| `correlation_id` | Trace ID for one run |

Errors appear with `"level":"error"` or on stderr: `error: ...`.

---

## 3. Command-line interface (CLI)

### Basic syntax

```bash
siclient --profile <path-to-profile.json> [options]
siclient --help
```

The profile path is **always required** (except `--help`).

### Common tasks

#### Register on IMS

Register and stay registered until you press Ctrl+C or the process exits:

```bash
siclient --profile profiles/lab-volte-01.json
```

Or with Make:

```bash
make register
make register PROFILE=profiles/my-operator.json
```

Success: log contains `registration complete` or `Registration flow complete; client is registered`.

#### Deregister (logout)

```bash
siclient --profile profiles/lab-volte-01.json --deregister
# or: make deregister
```

Sends `REGISTER` with `Expires: 0` to detach from IMS.

#### Place a voice call (MO)

```bash
siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org \
  --call-duration 10
```

The client will:

1. Register (if not already)
2. Send INVITE with SDP and preconditions
3. Complete PRACK/UPDATE handshake
4. Keep the call active for `--call-duration` seconds (default **2**)
5. Send BYE and exit

**With hold and DTMF:**

```bash
siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:callee@ims.example \
  --call-duration 15 --hold --dtmf 5
```

Or:

```bash
make mo-call MO_DEST=sip:callee@ims.example CALL_DURATION=15 HOLD=1 DTMF=5
```

#### Emergency call

```bash
siclient --profile profiles/lab-volte-01.json --emergency-call
siclient --profile profiles/lab-volte-01.json --emergency-call tel:112
```

Requires `services.emergency.enabled: true` in the profile. **Use only on lab cores** unless properly provisioned for real emergency routing.

#### Send SMS

```bash
siclient --profile profiles/lab-volte-01.json \
  --send-sms tel:+15551212 "Hello from IMS"
```

Requires `services.sms.enabled: true`.

#### Call forwarding (XCAP)

Enable unconditional forwarding:

```bash
siclient --profile profiles/lab-volte-01.json \
  --set-call-forwarding tel:+15559876
```

Read current rule:

```bash
siclient --profile profiles/lab-volte-01.json --fetch-call-forwarding
```

Requires `services.supplementary.enabled: true`.

### Full CLI option reference

| Option | Description |
|---|---|
| `--profile <path>` | Operator profile JSON (**required**) |
| `--dry-run` | Load profile only; no SIP |
| `--deregister` | Register then deregister |
| `--mo-call <uri>` | MO VoLTE call to SIP/tel URI |
| `--call-duration <sec>` | Seconds to keep call active (default 2) |
| `--hold` | Hold then resume during MO call |
| `--dtmf <digit>` | Send one DTMF digit (0–9, *, #) during call |
| `--emergency-call [uri]` | Emergency call (default tel:112) |
| `--send-sms <dest> <text>` | Send SMS after register |
| `--fetch-call-forwarding` | Read CFU via XCAP |
| `--set-call-forwarding <target>` | Enable CFU to target |
| `-h`, `--help` | Show usage |

---

## 4. Graphical interface (GUI)

Launch the lab console:

```bash
siclient-gui
# or: make run-gui
```

### Window layout

| Area | Contents |
|---|---|
| **Sidebar (form)** | Profile, registration, voice, SMS, supplementary, emergency controls |
| **Detail pane** | Status headline + scrollable activity log |

### Step-by-step: first call

1. **Profile path** — enter the full path, e.g. `/Users/you/siclient/profiles/lab-volte-01.json`
2. Click **Load profile** — sidebar shows profile summary (ID · domain · security)
3. Click **Register** — status changes to **Registered**; log shows `Registered`
4. **Destination URI** — enter callee, e.g. `sip:001010987654321@ims.mnc001.mcc001.3gppnetwork.org`
5. Click **Call** — status becomes **In call**
6. Optional: **Hold** / **Resume**, enter a digit and **Send** for DTMF
7. Click **Hang up** — status returns to **Registered**
8. Click **Deregister** when finished

### GUI controls reference

| Control | When enabled | Action |
|---|---|---|
| Load profile | Path entered | Parses and validates JSON |
| Register | Profile loaded, not registered | SIP REGISTER to P-CSCF |
| Deregister | Registered or in call | BYE active call + Expires: 0 |
| Call | Registered, destination set | MO INVITE |
| Hang up | In call | BYE |
| Hold / Resume | In call | re-INVITE sendonly/sendrecv |
| Send (DTMF) | In call, one digit entered | RFC 4733 telephone-event |
| Send SMS | Registered, dest + text filled | SIP MESSAGE |
| Enable CFU / Fetch CFU | Registered | XCAP PUT/GET |
| Emergency call (112) | Profile loaded, not in call | Register + emergency INVITE |

Buttons are greyed out when the action is not valid — e.g. **Call** requires registration first.

### Tips

- Use the **log pane** to diagnose failures; error messages appear there and in the status bar
- Profile path can be relative or absolute; relative paths depend on the current working directory
- The GUI uses the same profile and network stack as the CLI

---

## 5. Typical workflows

### Lab tester: verify registration

```bash
make dry-run
make register PROFILE=profiles/my-lab.json
# watch logs for "registration complete"
# Ctrl+C to stop
```

### Lab tester: MO voice call with media stats

```bash
siclient --profile profiles/lab-volte-01.json \
  --mo-call sip:peer@lab.ims \
  --call-duration 30
```

Look for log fields: `packets_sent`, `packets_received`, `jitter_ms`.

### Developer: run tests before demo

```bash
make test
make acceptance
```

### Operator acceptance (full suite)

See [operator-interop-runbook.md](operator-interop-runbook.md).

---

## 6. Profiles

Two sample profiles ship with the repo:

| File | Purpose |
|---|---|
| `profiles/lab-volte-01.json` | Standard lab VoLTE (AMR-WB, TLS, all services) |
| `profiles/lab-volte-evs-premium.json` | Premium codec order with EVS |

Create your own by copying and editing:

```bash
cp profiles/lab-volte-01.json profiles/my-operator.json
```

Key fields to change:

- `pcscf.address` / `port` — your P-CSCF
- `home_domain` — IMS domain
- `lab_sim.impi`, `impus`, `aka_vectors` — credentials from HSS

Never commit production credentials to git.

---

## 7. Troubleshooting

| Problem | Likely cause | What to do |
|---|---|---|
| `Missing required --profile` | No `--profile` flag | Add `--profile path/to.json` |
| `Profile not found` | Wrong path | Use absolute path; check file exists |
| `Missing required --profile` in GUI | Profile not loaded | Click **Load profile** first |
| Buttons greyed out | Wrong state | Register before calling; load profile first |
| Registration timeout | P-CSCF unreachable | Ping host/port; check firewall |
| 401 loop | Wrong AKA vectors | Match HSS; check AUTS resync |
| 403 Forbidden | IMPU not provisioned | Verify HSS subscription |
| TLS handshake fail | Cert mismatch | Set pin or `allow_insecure_lab` for lab |
| Call fails after register | Wrong callee URI | Use full SIP URI from lab directory |
| No RTP audio | Media disabled / firewall | Check `media` block; open RTP port |
| SMS fails | Service disabled | Set `services.sms.enabled: true` |
| Emergency fails | Service disabled | Set `services.emergency.enabled: true` |
| Secrets in logs | Bug or misconfig | Report; verify redaction in dry-run |

Enable verbose investigation with dry-run first, then register, then call — one step at a time.

---

## 8. FAQ

**Q: Do I need a SIM card?**  
A: No physical SIM on Mac. Lab profiles embed test credentials in `lab_sim`. Production deployments may use Keychain for IMPI/IMPU.

**Q: Can I receive incoming calls with the CLI?**  
A: The CLI focuses on MO flows. MT handling is tested via `SessionFSM` in automated tests. A host app or future GUI enhancement would expose MT UI.

**Q: What's the difference between CLI and GUI?**  
A: Same engine (`SICLientCore`). CLI is scriptable; GUI is interactive for manual lab testing.

**Q: Is this production-ready?**  
A: Lab-validated. See `spec.md` §8 production exit gate for remaining gaps (IPSec, licensed codecs, hardware SIM).

**Q: How do I place two calls at once?**  
A: Concurrent calls (1 active + 1 held) are supported in the library API. CLI/GUI expose single-call workflows today; use `CallService` programmatically for concurrent scenarios.

---

## 9. Related documents

| Document | When to read |
|---|---|
| [deployment-guide.md](deployment-guide.md) | Installing and configuring SICLient |
| [operator-interop-runbook.md](operator-interop-runbook.md) | Validating against operator IMS |
| [integration-guide.md](integration-guide.md) | Building SICLient into your app |
| [api-reference.md](api-reference.md) | API details for developers |
