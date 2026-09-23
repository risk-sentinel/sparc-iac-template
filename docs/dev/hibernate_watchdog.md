# Hibernate/Wake Desired-State Watchdog (#573)

A reliability safety net that replaces reliance on best-effort GitHub `schedule`
latency for prod's hibernate/wake transitions. On 2026-07-24 the wake cron fired
32 min late (prod down that whole time); GitHub crons have **unbounded latency**
and can drop entirely, with no monitoring.

## How it works

An **EventBridge Scheduler** schedule invokes a Lambda every ~5 minutes. Each
tick the Lambda:

1. Computes the **desired** state from the clock — DST-aware `America/New_York`,
   `06:00–21:00 ET` → `awake`, else `asleep`. (This also fixes the old fixed-UTC
   cron's EDT/EST drift.)
2. Reads the **actual** state — ECS `desiredCount` (hibernate sets it to 0, wake
   restores it; `>0` = awake).
3. On mismatch, `workflow_dispatch`es the **existing** `schedule-hibernate.yml`
   with `action=wake|hibernate` + `environment=prod`. All Terraform hibernate/
   wake logic stays untouched — the watchdog is just a reliable trigger.

Worst-case recovery is bounded to one check interval, independent of GitHub.

### Guards & monitoring

- **Flapping guard:** skips dispatch if a hibernate/wake run is already in
  progress.
- **Drift-correction metric** (`SPARC/Hibernate` → `HibernateDriftCorrected`) +
  alarm — fires whenever the watchdog had to *correct* a transition that did not
  happen on its own, surfacing persistent primary-trigger problems.
- **Self-monitoring alarm** on the watchdog Lambda's own `Errors`.

### Why the Lambda runs OUTSIDE the VPC (critical)

Hibernate destroys the NAT gateway. A private-subnet Lambda would lose internet
egress exactly when it must call GitHub to wake prod — a deadlock. The function
has **no `vpc_config`** and uses AWS-managed egress, independent of the NAT it
manages. (Enforced-by-omission; checkov `CKV_AWS_117` is skipped with this
rationale.)

### GitHub credential

The Lambda reuses the org GitHub App (`sparc-iac-diagram-bot`). Per invocation it
reads the App id/installation/private-key from Secrets Manager, signs a
short-lived **RS256 JWT (pure-stdlib — no `cryptography`/PyJWT to package)**, and
exchanges it for a ~1 h installation token. No long-lived credential to rotate.

## Operator setup (one-time)

The watchdog is gated off by default (`enable_hibernate_watchdog = false`).

1. **Grant the GitHub App `Actions: write` on `risk-sentinel/sparc-iac`.** The
   diagram-bot App today has `Contents: write` (for diagram/perf commits); the
   watchdog additionally needs `Actions: write` to `workflow_dispatch`. Add it in
   the App's repository permissions, then accept the permission update on the
   installation.
2. **Apply order (split deploy, like #565):**
   - Operator applies `bootstrap/oidc` first — grants `ci-execute` the new
     `scheduler:*` surface (policy + permissions boundary). Without this the ECS
     deploy fails `AccessDenied`.
   - Then set `enable_hibernate_watchdog = true` and deploy `AWS/ECS` (creates
     the Lambda, schedule, IAM roles, alarms, and the secret shell).
3. **Populate the secret** `<project>-<env>/hibernate-watchdog-gh-app` with JSON
   (the private key stays out of Terraform state):

   ```json
   {
     "app_id": "123456",
     "installation_id": "12345678",
     "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n"
   }
   ```

   Both PKCS#1 (`BEGIN RSA PRIVATE KEY`) and PKCS#8 (`BEGIN PRIVATE KEY`) are
   accepted.

## Phasing

- **Phase 1 (done, validated 2026-07-25/26):** watchdog ran **alongside** the
  existing GitHub crons. Proven end-to-end on a full cycle — hibernate at 21:20 ET
  and wake at 06:04 ET, both watchdog-driven and on-time, ~1h ahead of the drifted
  crons.
- **Phase 2 (done):** the GitHub `schedule:` crons in `schedule-hibernate.yml`
  are retired — the watchdog is now the **sole automated trigger** (avoids the
  drifted double-firing seen in Phase 1). `workflow_dispatch` is retained so the
  watchdog and manual runs still work.

If the watchdog itself ever needs to be bypassed (e.g., during an incident), the
crons can be temporarily re-added to `on.schedule` in `schedule-hibernate.yml`;
the `Resolve action` step would need its schedule branch restored too.

## Validate

Induce drift and confirm self-heal:

- During the awake window, manually `hibernate` prod (or scale the service to 0).
  Within one interval the watchdog should dispatch `wake`, `HibernateDriftCorrected`
  should increment, and the drift alarm should fire.
- Check the Lambda logs (`/aws/lambda/<project>-<env>-hibernate-watchdog`) for the
  `OK:` / `DRIFT` lines each tick.

## Rollback

Set `enable_hibernate_watchdog = false` and redeploy (removes the schedule,
Lambda, roles, alarms, and secret shell), or disable the schedule in the console
for an immediate stop.

Since Phase 2 retired the GitHub crons, the watchdog is the **sole** automated
trigger — disabling it stops all automated hibernate/wake. If you disable it,
either re-add the `schedule:` crons to `schedule-hibernate.yml` (restore the
`Resolve action` schedule branch too) or drive transitions manually via
`workflow_dispatch` until the watchdog is restored.
