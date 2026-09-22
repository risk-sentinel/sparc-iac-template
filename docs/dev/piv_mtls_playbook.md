# SPARC PIV / mTLS Playbook (#559)

Phishing-resistant **PIV/CAC (client-certificate) authentication** for SPARC over
mutual TLS — **IA-2(12)** (Acceptance of PIV Credentials), **IA-5(2)** (PKI
validation/revocation), **IA-2(6)** (auth from a separate device). App-side
consumption ships in `sparc` behind `SPARC_ENABLE_PIV` (v1.13.2, pinned via #585);
this repo provides the mTLS termination.

## Architecture — single listener, no split

```
Browser (PIV/CAC+PIN, or OIDC/local — no cert)
  └─ TLS ─▶ ALB :443 (existing HTTPS listener, WAF #578 attached)
              mutual_authentication = passthrough
              • requests a client cert (OPTIONAL — cert-less OIDC users proceed)
              • forwards the presented cert chain as X-Amzn-Mtls-Clientcert
              • owns the X-Amzn-Mtls-* headers → clients cannot spoof them
              └─▶ nginx sidecar (unchanged HTTP proxy)
                    └─▶ SPARC: SPARC_ENABLE_PIV reads X-Amzn-Mtls-Clientcert,
                        parses identity, #804 issuer/policy filter, #805 require-methods
```

**One listener. No NLB, no second hostname, no nginx TLS termination, no nginx
image change.** The ALB keeps terminating TLS and keeps WAF #578; PIV and OIDC
share the single `:443` listener. This is the only AWS-native way to serve both
cert and cert-less clients on one listener while retaining the ALB WAF.

### Passthrough vs verify (why passthrough)
`verify` mode rejects cert-less clients at the handshake → breaks OIDC.
`passthrough` allows cert-less and forwards the cert for the app to consume, so
both auth types coexist. The ALB does not chain-validate in passthrough; SPARC's
`#804` issuer/policy filter is the app-side control, and the ALB-owned
`X-Amzn-Mtls-*` headers provide the anti-spoof (a client can't inject them).

## Certificates
| Role | Source | Where |
| --- | --- | --- |
| **Server TLS** (`sparc.example.com`) | ACM (existing) | ALB HTTPS listener — unchanged |
| **Client PIV cert** | org PIV CA (or ACM Private CA) | YubiKey **slot 9A** (`scratchpad/piv-test/`) |

No trust store is required on the ALB for `passthrough`. Load the org PIV CA into
`SPARC_PIV_ACCEPTED_ISSUERS` (issuer filter) as the app-side trust signal.

## Terraform (gated behind `enable_piv_mtls`, default off)
- `modules/alb`: `dynamic "mutual_authentication" { mode = "passthrough" }` on the
  HTTPS listener — empty (mode off) when disabled, so the listener is unchanged.
- `modules/ecs_fargate` + `envs/prod/sparc-task-definition.json`: SPARC PIV env —
  `SPARC_ENABLE_PIV` (tracks the flag), `SPARC_PIV_CERT_HEADER=X-Amzn-Mtls-Clientcert`,
  `SPARC_PIV_IDENTITY_SOURCE` (`sparc_piv_identity_source`, default `email`),
  `SPARC_REQUIRE_AUTH_METHODS` (`sparc_require_auth_methods`, default empty),
  `SPARC_PIV_ACCEPTED_ISSUERS` (`sparc_piv_accepted_issuers`).
- Wired root → `alb`/`ecs_fargate`; `enable_piv_mtls=false` renders the task-def
  and listener byte-identical to today → **no redeploy, no prod impact** when off.

## Enable (when ready to test)
In `envs/prod/terraform.tfvars`:
```hcl
enable_piv_mtls            = true
sparc_piv_identity_source  = "email"            # maps the SAN email to a SPARC user
sparc_piv_accepted_issuers = "Risk-Sentinel SPARC Test PIV CA"   # or your org CA DN
# sparc_require_auth_methods = "oidc,piv"        # only once you want to ENFORCE it
```
Then deploy. The YubiKey (slot 9A, `brandon.field@example.com`) is already
provisioned; ensure a matching SPARC user exists.

## Anti-spoof (satisfied by the ALB)
The ALB sets `X-Amzn-Mtls-Clientcert` and strips client-supplied `X-Amzn-Mtls-*`
copies, so SPARC's cert header can't be forged. **AC:** confirm the app is
reachable only via the ALB (SG isolation), and a request with a hand-set
`X-Amzn-Mtls-Clientcert` to the app origin is rejected/unreachable.

## Testing
- No-YubiKey chain check: `openssl verify -CAfile org-piv-ca.crt testuser.crt`.
- With the card: browse `https://sparc.example.com` — the browser prompts
  for the PIV cert (enter PIN); SPARC maps `brandon.field@example.com` and
  logs in. Cert-less → OIDC/local still works. (`scratchpad/piv-test/PROVISIONING.md`.)

## Follow-ons
- Revocation (IA-5(2)) — passthrough doesn't CRL; add OCSP/CRL app-side or a
  verify-mode option if DoD PKI is required later.
- Extend WAF/coverage to the PIV path is automatic (same ALB listener + WAF #578).
