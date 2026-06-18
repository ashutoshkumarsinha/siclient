# SIPp IMS Digest Auth Scenarios

SIPp scenarios for IMS-AKA two-step REGISTER with **SIP Digest** authentication.

## Files

| File | Role |
|---|---|
| `register_aka.xml` | UAC: standard SIP Digest (MD5) two-step REGISTER |
| `register_aka_ims.xml` | UAC: AKAv1-MD5 shaped REGISTER for real IMS cores |
| `deregister.xml` | UAC: deregister with two-step digest (`Expires: 0`) |
| `register_deregister.xml` | UAC: register + deregister in one call (reuses digest state) |
| `mo_volte_precondition.xml` | UAC: MO INVITE with 183/PRACK and RFC 3312 SDP |
| `mt_volte.xml` | UAS: MT answer with 180/183, precondition SDP, PRACK |
| `uas_volte_call.xml` | UAS: network-side MO callee (183/PRACK/200) |
| `pcscf_register_uas.xml` | UAS: mock P-CSCF with `WWW-Authenticate` + `verifyauth` validation |
| `lab-volte-01.csv` | Injected fields: domain, IMPU, IMPI, MD5 password, callee URI |
| `lab-volte-01-ims.csv` | IMS AKA fields including AUTN and RAND||AUTN nonce |
| `digest-auth.env` | Lab IMPI, RES hex, auth URI |
| `sipp-digest-auth.sh` | Shared `-au` / `-ap` / `-auth_uri` / `-inf` flags |
| `run-*.sh` | Convenience wrappers |

## SIP Digest flow

1. **First REGISTER** — empty `Authorization: Digest ... response=""`
2. **401** — `recv response="401" auth="true"` stores `WWW-Authenticate` challenge
3. **Second REGISTER** — `[authentication]` (SIPp emits the full `Authorization: Digest ...` header)

For **MD5 Digest** loopback testing, `-ap` is `MD5_PASSWORD` from `digest-auth.env`.

For **AKAv1-MD5** against a real IMS core, use `register_aka_ims.xml` with `SIPP_IMS_DIGEST_FLAGS` / `lab-volte-01-ims.csv` and `-ap` set to `AKA_SECRET_HEX` (IK || CK).

## Acceptance suite

Run the full lab acceptance pipeline (122 Swift tests, CLI bootstrap, GUI smoke, optional SIPp):

```bash
chmod +x Tests/sipp/run-acceptance.sh Tests/gui/run-gui-smoke.sh
./Tests/sipp/run-acceptance.sh
```

Individual steps:

```bash
swift test                    # all unit + integration tests
./Tests/gui/run-gui-smoke.sh  # GUI build + ViewModel tests only
```

## Quick start (SIPp UAS + UAC loopback)

Terminal 1 — mock P-CSCF:

```bash
chmod +x Tests/sipp/run-uas.sh
./Tests/sipp/run-uas.sh 127.0.0.1 15060
```

Terminal 2 — register:

```bash
chmod +x Tests/sipp/run-register.sh
./Tests/sipp/run-register.sh 127.0.0.1:15060
```

Register + deregister in one flow:

```bash
./Tests/sipp/run-register-deregister.sh 127.0.0.1:15060
```

MO VoLTE with preconditions (two terminals):

```bash
./Tests/sipp/run-uas-volte.sh 127.0.0.1 15060   # terminal 1
./Tests/sipp/run-mo-call.sh 127.0.0.1:15060     # terminal 2
```

MT VoLTE (UAS + caller in one script):

```bash
./Tests/sipp/run-mt-call.sh 127.0.0.1 15061
```

## Manual SIPp command

```bash
sipp -sf Tests/sipp/register_aka.xml \
  -inf Tests/sipp/lab-volte-01.csv \
  -au "001010123456789@ims.mnc001.mcc001.3gppnetwork.org" \
  -ap "lab-volte-secret" \
  -auth_uri "ims.mnc001.mcc001.3gppnetwork.org" \
  <pcscf-host>:<port> -m 1
```

## UAS digest validation

`pcscf_register_uas.xml` uses `verifyauth` on the second `REGISTER` to validate the
`Authorization: Digest` header against `[field2]` (IMPI) and `[field3]` (MD5 password)
from `lab-volte-01.csv`. The UAC side uses the same credentials via `-au` / `-ap`.

## Notes

- `[authentication]` must be on its own line — SIPp expands it to the full `Authorization: Digest ...` header (do not prefix with `Authorization:`).
- `-auth_uri` should be the registrar domain **without** the `sip:` prefix (e.g. `ims.mnc001.mcc001.3gppnetwork.org`).
- `register_deregister.xml` reuses digest credentials from the same `Call-ID` for deregister (no second 401).
- Against **SICLient** `MockPCSCFResponder`, use `swift test` integration tests; SIPp AKAv1-MD5 response format may differ from the Swift client's base64(RES) encoding.
