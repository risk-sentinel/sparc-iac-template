# FIDO2 / WebAuthn security-key sign-in — operator & rollout guide

How to deploy and roll out **FIDO2/WebAuthn** security-key authentication for SPARC:
org-issued USB tokens (YubiKey, Feitian, Token2, Nitrokey, …) or platform
passkeys, giving phishing-resistant MFA (key + PIN = possession + knowledge in
one ceremony).

> **FIDO2 ≠ PIV/CAC.** This guide is for FIDO2 (an on-device keypair, no
> certificate, app-native). The certificate-on-a-card path (PIV/CAC, incl. the
> YubiKey PIV applet) is a different mechanism that needs an mTLS gateway — see
> [Choosing FIDO2 vs PIV](#choosing-fido2-vs-piv) and `sparc-iac#559`.

## Deployment (IaC) — what the operator sets

FIDO2 is **app-native**: no gateway, no trust store, no new AWS infrastructure,
no IAM, no secrets. One environment variable:

| Variable | Value | Notes |
|---|---|---|
| `SPARC_FIDO2_ENABLED` | `true` | The only required setting. Set in `AWS/ECS/envs/prod/sparc-task-definition.json`. |
| `SPARC_FIDO2_RP_ID` | *(unset)* | Defaults to the host of `SPARC_APP_URL` (`sparc.example.com`). **Must match the browser origin.** Set only to scope credentials to a parent domain. |
| `SPARC_FIDO2_RP_NAME` | *(unset)* | Defaults to `SPARC_APP_NAME`. Display name the authenticator shows. |

Because `SPARC_APP_URL` is already the externally-visible HTTPS origin, the
default RP ID/name are correct and nothing else is required. Enabling is
**additive and opt-in** — password/OIDC/LDAP login are unaffected; only users
who enroll a key can use it.

Enabling forces a task-def replace + rolling redeploy (deploy in the awake
window). Landed in PR #577.

## The enrollment model — read this before planning a rollout

**FIDO2 credentials cannot be centrally pre-provisioned or bulk-loaded. By
design.** When a user registers a key, the keypair is generated *on the device*
during an interactive ceremony requiring user presence (touch) and user
verification (PIN), and is bound to *(that user account + our origin)*. The
private key never leaves the token and does not exist until enrollment. There is
no "push these credentials to N users" operation — that would defeat the
phishing-resistance guarantee.

**So each user self-enrolls their own key.** You cannot federate or mass-enroll
FIDO2 credentials in the pre-loaded sense. What you *can* do is make it a managed
rollout:

### Recommended rollout for org-issued keys

1. **Procure** org-issued FIDO2 tokens (any FIDO2-certified brand — not limited
   to YubiKey, and none of this is PIV/CAC).
2. **Pre-set a FIDO2 PIN** on each token (e.g. via YubiKey Manager) before
   handing it out — the PIN is the "knowledge" factor.
3. **Distribute** the tokens to users.
4. **Users self-enroll** (one tap each): sign in with their existing method →
   **Security Keys** page → register the token (insert, touch, enter PIN).
5. **Users then sign in** either email-first (type email → key + PIN) or
   usernameless (resident key → key + PIN, no email).

This is bulk *distribution* + per-user *enrollment* — the standard enterprise
pattern. Point users at the SPARC **Security Keys & Smart Cards** user guide
(in-app Help Center → the `?` on the Security Keys page, or the wiki).

### Restricting to org-issued keys (optional)

**Enterprise attestation** can constrain enrollment to company-issued tokens by
their AAGUID, so a user can't register a random personal key. This is federated
*trust*, not federated *provisioning*. Whether SPARC exposes an attestation
policy is an app-side question — confirm with the SPARC team before relying on
it.

### ⚠️ Enrollment gotcha: the browser offers the built-in authenticator first

On **macOS** (and **Windows**), when a user clicks *Register / Add a security
key*, the OS/browser dialog defaults to the **built-in platform authenticator**
— Touch ID / an iCloud passkey on Mac, Windows Hello on Windows — **not** the
inserted USB token. Users must expand **"More options" / "Use a different
device" / "Security key"** (wording varies by browser) to route the ceremony to
the physical YubiKey.

This is standard WebAuthn platform behavior, **not a SPARC bug** — but it will
stop nearly every first-time enroller who expects the inserted key to be picked
up automatically. **Call it out explicitly in the enrollment instructions you
hand to users.** Inserting the token and Yubico Authenticator seeing it do *not*
start enrollment; only the on-page Register button + selecting "security key" in
the browser dialog does.

(If org policy is to standardize on the physical token and *avoid* platform
passkeys, that's an org decision at distribution time — WebAuthn will still offer
both; the guidance to users is what steers them to the USB key.)

### Lockout recovery

By design there are **no self-service backup codes**. If a user loses their key,
recovery is an **admin key-reset** (an admin clears the user's registered keys so
they can re-enroll). Establish and test this runbook before rolling FIDO2 to real
users.

## Testing (post-deploy)

The physical key-tap cannot be automated; this is a human-in-the-loop test
against the **prod origin** (`https://sparc.example.com` — a key registered
on any other origin will not work here):

1. Sign in as a test user → **Security Keys** → enroll the token.
2. Sign out → sign in passwordless (email + key/PIN, and usernameless).
3. Verify a **wrong PIN** and a **wrong key** are rejected.
4. Exercise the **admin key-reset** recovery path.

## Choosing FIDO2 vs PIV

| You want… | Use | Central bulk provisioning? | Available |
|---|---|---|---|
| Phishing-resistant USB token, app-native | **FIDO2** (this guide) | No — self-enroll per user | now |
| Centrally-issued, mass-provisioned tokens | **PIV** (private-CA, incl. YubiKey PIV applet) | Yes — issue certs in bulk | needs the mTLS gateway, `sparc-iac#559` |

If en-masse central provisioning without a per-user ceremony is a hard
requirement, FIDO2 is the wrong tool — that is the certificate model, and it can
run against your **own private CA** (not DoD). The app-side contract for that is
documented in the SPARC repo (`docs/PIV_IDENTITY_MAPPING.md`, which includes a
non-DoD worked example); the transport/mTLS gateway is `sparc-iac#559`.

## Compliance

FIDO2/WebAuthn delivers app-native MFA that is **replay- and phishing-resistant**
(per-ceremony challenge, origin binding, signature-counter clone detection):
**IA-2(1)/(2)** (MFA, no longer conditional on an external IdP) and **IA-2(8)**
(replay/phishing resistance). Distinct from IA-2(12) (PIV acceptance), which is
the PIV/CAC path.
