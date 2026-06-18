# SICLient Deployment Guide

This guide covers building, installing, configuring, and operating SICLient on macOS Tahoe for **lab** and **pre-production** deployments. For day-to-day usage after install, see [user-guide.md](user-guide.md).

---

## 1. Overview

SICLient ships as two executables plus a Swift library:

| Artifact | Product | Purpose |
|---|---|---|
| `siclient` | CLI | Scriptable IMS client for lab automation and CI |
| `siclient-gui` | SwiftUI app | Interactive lab console |
| `SICLientCore` | Library | Embed in host macOS apps |

**Supported platform:** macOS 26 (Tahoe) or later, Apple Silicon or Intel.

**Not supported today:** iOS, Linux, Windows, containerized headless GUI, hardware ISIM/PCSC on Mac.

---

## 2. Prerequisites

### Developer / lab machine

| Requirement | Version |
|---|---|
| macOS | 26+ (Tahoe) |
| Xcode | 26+ (includes Swift 6.2+ toolchain) |
| Network | Reachable P-CSCF on Gm (UDP/TCP/TLS per profile) |

Verify toolchain:

```bash
swift --version
xcode-select -p
```

### Operator IMS lab

- P-CSCF address and port (static, PCO, DHCP, or DNS SRV)
- HSS-provisioned IMPI/IMPU and AKA vectors (lab profile) or Keychain credentials
- Firewall rules allowing:
  - SIP signaling to P-CSCF (typically UDP/TCP **5060**, TLS **5061**)
  - RTP/RTCP to media plane (profile `media.local_rtp_port`, default **40000**)

---

## 3. Build

### Debug (development)

```bash
git clone <repo-url> siclient && cd siclient
make build                 # CLI + GUI
make test                  # 122 tests
```

Binaries: `.build/debug/siclient`, `.build/debug/siclient-gui`

### Release (deployment)

```bash
swift build -c release --product siclient
swift build -c release --product siclient-gui
```

Binaries: `.build/release/siclient`, `.build/release/siclient-gui`

Release builds are smaller and faster — use these for lab machines that run calls repeatedly.

### Makefile reference

```bash
make help          # all targets
make build         # debug build
make test
make acceptance    # full acceptance suite
make clean
```

---

## 4. Install

### Option A — Run from build tree (simplest)

```bash
export PATH="$PWD/.build/release:$PATH"
siclient --profile profiles/lab-volte-01.json --dry-run
```

### Option B — Copy to `/usr/local/bin`

```bash
swift build -c release
sudo install -m 755 .build/release/siclient /usr/local/bin/
sudo install -m 755 .build/release/siclient-gui /usr/local/bin/
```

### Option C — Dedicated install prefix

```bash
PREFIX=/opt/siclient
mkdir -p "$PREFIX/bin" "$PREFIX/profiles"
swift build -c release
install -m 755 .build/release/siclient "$PREFIX/bin/"
install -m 755 .build/release/siclient-gui "$PREFIX/bin/"
cp -R profiles/* "$PREFIX/profiles/"
```

Add to shell profile:

```bash
export PATH="/opt/siclient/bin:$PATH"
export SICLIENT_PROFILE="/opt/siclient/profiles/lab-volte-01.json"
```

### GUI app bundle (optional)

For a double-clickable app, open `Package.swift` in Xcode, select the **siclient-gui** scheme, and **Product → Archive**. Alternatively, wrap the release binary in a minimal `.app` bundle with `Info.plist` — not provided by default.

---

## 5. Configuration

### Operator profile

Every deployment needs one JSON profile per operator/PLMN. Start from a template:

```bash
cp profiles/lab-volte-01.json profiles/my-operator.json
```

Edit these sections for your network:

| Section | What to set |
|---|---|
| `profile_id` | Unique name for logs |
| `home_domain` | IMS domain (e.g. `ims.mnc001.mcc001.3gppnetwork.org`) |
| `pcscf` | P-CSCF discovery mode and address |
| `security` | `tls` or `ipsec` policy; pinning fingerprints |
| `lab_sim` | IMPI, IMPUs, AKA vectors (lab only — remove for Keychain) |
| `media` | RTP port, codec flags |
| `services` | Enable emergency, SMS, XCAP, handover as needed |

Validate before deploy:

```bash
siclient --profile profiles/my-operator.json --dry-run
```

Expected log line: `"message":"SICLient bootstrap complete"`.

### P-CSCF discovery modes

| Mode | Profile | Environment override |
|---|---|---|
| Static | `"mode": "static", "address": "10.0.0.1", "port": 5060` | — |
| PCO | `"mode": "pco", "pco_addresses": ["10.0.0.1:5060"]` | `SICLIENT_PCO_PCSCF=10.0.0.1:5060` |
| DHCP | `"mode": "dhcp", "dhcp_addresses": [...]` | `SICLIENT_DHCP_PCSCF=10.0.0.1:5060` |
| DNS SRV | `"mode": "srv", "srv_domain": "ims.example.com"` | Resolved via `ProductionNetworkAdapter` |

### TLS (production-style)

```json
"security": {
  "mechanism": "tls",
  "tls": {
    "allow_insecure_lab": false,
    "pinned_cert_sha256": ["a1b2c3d4..."]
  }
}
```

Obtain P-CSCF certificate fingerprint:

```bash
openssl s_client -connect pcscf.example.com:5061 </dev/null 2>/dev/null \
  | openssl x509 -outform DER | openssl dgst -sha256
```

For self-signed lab cores, set `"allow_insecure_lab": true` **only in lab profiles**.

### Keychain credentials (no `lab_sim` in profile)

Store IMS identities in macOS Keychain:

| Keychain item | Account suffix | Example value |
|---|---|---|
| Service | `com.siclient.imsi` | — |
| Account | `<prefix>.impi` | `001010123456789@ims.mnc001.mcc001.3gppnetwork.org` |
| Account | `<prefix>.impus` | `sip:user@ims.example,tel:+15551234567` |

Set environment variable before launch:

```bash
export SICLIENT_KEYCHAIN_ACCOUNT=my-lab-subscriber
siclient --profile profiles/production-no-labsim.json
```

**Note:** Keychain adapter provides IMPI/IMPU only. AKA challenges still require `lab_sim` vectors or a future hardware SIM adapter.

### Environment variables summary

| Variable | Purpose |
|---|---|
| `SICLIENT_KEYCHAIN_ACCOUNT` | Keychain account prefix for IMPI/IMPU |
| `SICLIENT_PCO_PCSCF` | Override PCO P-CSCF list (`host:port`) |
| `SICLIENT_DHCP_PCSCF` | Override DHCP P-CSCF list |

---

## 6. Deployment topologies

### Lab UE against PyHSS / Kamailio

```
Mac (siclient) ──Gm/SIP──► P-CSCF ──► S-CSCF ──► HSS
                └──RTP──► media server / peer UE
```

1. Deploy profile with lab AKA vectors matching HSS
2. `make dry-run` → `make register`
3. Run acceptance: `make acceptance`

### CI / headless automation

GitHub Actions workflow (`.github/workflows/ci.yml`) runs on `macos-26`:

```yaml
- run: swift build -v
- run: test -x .build/debug/siclient-gui
- run: swift test -v
- run: swift run siclient --profile profiles/lab-volte-01.json --dry-run
```

Local CI mirror:

```bash
make acceptance
```

No display server required — GUI tests exercise `ClientViewModel` only.

### Embedded in host app

Link `SICLientCore` from your Xcode project or SPM dependency. See [integration-guide.md](integration-guide.md). Deploy profile JSON in your app bundle:

```swift
let url = Bundle.main.url(forResource: "operator", withExtension: "json")!
let profile = try ProfileLoader.load(from: url)
```

---

## 7. Post-deploy verification

| Step | Command | Pass criteria |
|---|---|---|
| Build | `make build` | Exit 0 |
| Unit tests | `make test` | 122/122 pass |
| Bootstrap | `make dry-run` | `bootstrap complete` in JSON log |
| Register | `make register PROFILE=profiles/my-operator.json` | `registration complete` |
| MO call | `make mo-call PROFILE=... MO_DEST=sip:peer@domain` | `MO call established` |
| Secret redaction | grep logs for `res`/`ik`/`ck` hex | No key material in output |

Full operator interop checklist: [operator-interop-runbook.md](operator-interop-runbook.md).

---

## 8. Operations

### Logging

SICLient emits **JSON structured logs** to stdout. Each line includes:

- `correlation_id` — trace one session end-to-end
- `level` — `info`, `warn`, `error`
- `message` — human-readable event
- `fields` — structured context (profile_id, pcscf, codec, etc.)

Secrets (RES, IK, CK, AUTN) are redacted by `SecretRedactor`. If sensitive material appears in logs, treat it as a deployment misconfiguration.

Pipe to your log aggregator:

```bash
siclient --profile profiles/my-operator.json 2>&1 | tee -a /var/log/siclient.log
```

### Profile hot-reload

For long-running host apps using `ProfileManager`:

```swift
try profileManager.reload(fromPath: path)
```

CLI/GUI restart required for profile changes today.

### Upgrades

1. Run `make test` on the new version
2. Back up operator profiles and Keychain entries
3. Install new binaries over old (`install -m 755 ...`)
4. Re-run `make dry-run` and a test registration

### Rollback

Keep previous release binaries:

```bash
cp /opt/siclient/bin/siclient /opt/siclient/bin/siclient.bak
# restore from backup on failure
```

---

## 9. Security checklist

| Item | Lab | Production target |
|---|---|---|
| AKA vectors in profile JSON | Acceptable | **Remove** — use Keychain/SIM |
| `allow_insecure_lab: true` | OK for self-signed | **Must be false** |
| Certificate pinning | Optional | **Required** |
| Log redaction | Verified in CI | Monitor in production |
| RTP firewall | Open lab ports only | Restrict to media GW |
| Emergency calls | Lab routing only | Real E-CSCF provisioning |

---

## 10. Known limitations

| Limitation | Workaround |
|---|---|
| No hardware ISIM on Mac | Use `lab_sim` AKA vectors or Keychain for identities |
| IPSec-3GPP SA not implemented | Use TLS to P-CSCF (ADR 0001) |
| Keychain adapter has no AKA | Keep `lab_sim.aka_vectors` for authentication |
| GUI is lab tool, not production Ut | Embed `SICLientCore` for product UI |
| Licensed AMR/EVS codecs | Integrator supplies codec stack |

See `spec.md` §14 for full lab vs production fidelity matrix.

---

## 11. Related documents

| Document | Audience |
|---|---|
| [user-guide.md](user-guide.md) | Operators and testers using CLI/GUI |
| [integration-guide.md](integration-guide.md) | Developers embedding SICLientCore |
| [operator-interop-runbook.md](operator-interop-runbook.md) | IMS lab validation against real cores |
| [api-reference.md](api-reference.md) | Public API surface |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Module map |
