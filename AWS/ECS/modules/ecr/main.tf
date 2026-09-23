data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"

  # --- Cosign-safe ECR lifecycle policy (#515) -----------------------------
  # Retention is deliberately count-based and NEVER uses `tagStatus: untagged`.
  # Cosign stores signatures/attestations as OCI referrers (untagged
  # `sigstore.bundle` manifests, subject:true); heimdall2/vulcan additionally
  # carry the LEGACY tag-based `sha256-<digest>.sig`/`.att` scheme. An
  # untagged-expire rule — or an *unfiltered* tagged-count rule — would delete
  # live signatures and break `cosign verify` on the deploy gate.
  #
  # --- Two-tier retention (#707) -------------------------------------------
  # Rule 1 claims prerelease and per-architecture tags (`v*-*`). Rule 2 keeps the
  # N newest **v*-tagged** versions; `["v*"]` provably excludes `.sig`/`.att`/
  # `latest` and all untagged referrers. Rule 3 is a total-count backstop that
  # only reaps orphaned referrers (whose subject image is already gone) — ECR
  # protects live subject-bound referrers regardless.
  #
  # Rule 1 exists because `v*` matches `v1.16.1-rc3` and `v1.16.2-linux-amd64`
  # too, so throwaway tags competed with releases for the keep-N budget. On
  # 2026-09-18 that expired the image the RUNNING task definition pinned: six
  # `v*` tags (three rc builds plus a release and its two per-arch staging tags)
  # against a budget of five. Prod could not wake for ~11 hours (#707).
  #
  # The ordering is what fixes it, not the 7-day window. A higher-priority rule
  # CLAIMS its matches and removes them from every lower-priority rule, whether
  # or not it expires them on that pass — verified with
  # `start-lifecycle-policy-preview`: with rule 2 probed at keep=1 against nine
  # `v*` images, it expired exactly ONE, having only ever seen the two unsuffixed
  # tags. So prereleases are structurally incapable of evicting a release.
  #
  # `tagPatternList` has no negation; `v*-*` needs a literal hyphen, which is the
  # whole trick. **A hyphen therefore means DISPOSABLE here** — a future
  # `v1.17.0-fips` would be reaped after `prerelease_retain_days`.
  #
  # Expiring a per-arch TAG does not harm the released index: the tag is the
  # single-arch staging archive (`v1.16.2-linux-amd64` = `sha256:49d523c7…`),
  # while the index's child is a different, untagged manifest
  # (`sha256:9a4b80b8…`) that ECR protects while the index lives. Proven by a
  # worst-case preview: zero children of v1.16.0/v1.16.2 in the expiry set.
  #
  # Expiry does NOT delete an image's cosign signatures in the same pass — they
  # become orphaned referrers and are reaped later by rule 3. That lag is
  # deliberate; a `tagStatus:untagged` rule would delete LIVE signatures (#515).
  #
  # Every change is validated with `aws ecr start-lifecycle-policy-preview`
  # before apply.
  ecr_lifecycle_policy = { for n in distinct([var.tagged_retain_count, var.app_tagged_retain_count]) : n => jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire prerelease + per-arch tags (v*-*) after ${var.prerelease_retain_days} days (#707)"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["v*-*"]
          countType      = "sinceImagePushed"
          countUnit      = "days"
          countNumber    = var.prerelease_retain_days
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 2
        description  = "Keep the ${n} most-recent v*-tagged versions (cosign-safe: excludes .sig/.att/latest + untagged referrers)"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["v*"]
          countType      = "imageCountMoreThan"
          countNumber    = n
        }
        action = { type = "expire" }
      },
      {
        rulePriority = 3
        description  = "Backstop: retain last ${var.max_image_count} total (reaps orphaned referrers only; never a live signature)"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = var.max_image_count
        }
        action = { type = "expire" }
      }
    ]
  }) }
}

# ---------------------------------------------------------------------------
# ECR Repository
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "main" {
  name                 = local.name_prefix
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = "${local.name_prefix}-ecr"
  }
}

# ---------------------------------------------------------------------------
# Lifecycle Policy — retain last N images
# ---------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "main" {
  repository = aws_ecr_repository.main.name

  # Primary SPARC app repo — deeper versioned retention (see locals, #515).
  policy = local.ecr_lifecycle_policy[var.app_tagged_retain_count]
}

# ---------------------------------------------------------------------------
# NGINX Sidecar Repository
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "nginx" {
  name                 = "${local.name_prefix}-nginx"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = "${local.name_prefix}-nginx-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name

  policy = local.ecr_lifecycle_policy[var.tagged_retain_count]
}

# ---------------------------------------------------------------------------
# Adopted standalone-app repositories (#387) — UNPREFIXED.
#
# vulcan + heimdall2 are org-adopted standalone apps published by
# risk-sentinel/container-build-sign, not SPARC example-* images, so their
# repo names are literal (no name_prefix). Both pre-existed as MUTABLE / no
# scan-on-push and are brought under management here (imported via the import {}
# blocks in AWS/ECS/main.tf) and hardened to match the nginx posture: IMMUTABLE
# tags + scan-on-push + retain-last-N. Encryption stays AES256 (kms_key_arn=null)
# to match the live repos — changing encryption is ForceNew and would replace the
# prod-consumed repo. Push access is granted to the container-build-sign-publisher
# role in modules/iam/container_build_sign.tf.
# ---------------------------------------------------------------------------

resource "aws_ecr_repository" "vulcan" {
  name                 = "vulcan"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = "vulcan-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "vulcan" {
  repository = aws_ecr_repository.vulcan.name

  policy = local.ecr_lifecycle_policy[var.tagged_retain_count]
}

resource "aws_ecr_repository" "heimdall2" {
  name                 = "heimdall2"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = "heimdall2-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "heimdall2" {
  repository = aws_ecr_repository.heimdall2.name

  policy = local.ecr_lifecycle_policy[var.tagged_retain_count]
}

# container-build-sign publishes the CI runner image here to cut Docker Hub
# pulls (#438/#461). Push grant in AWS/IAM/container_build_sign.tf.
resource "aws_ecr_repository" "ci_runner" {
  name                 = "sparc-ci-runner"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = "sparc-ci-runner-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "ci_runner" {
  repository = aws_ecr_repository.ci_runner.name

  policy = local.ecr_lifecycle_policy[var.tagged_retain_count]
}

# container-build-sign publishes the auditor image here (#438).
resource "aws_ecr_repository" "auditor" {
  name                 = "sparc-auditor"
  image_tag_mutability = var.image_tag_mutability
  force_delete         = false

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = var.kms_key_arn != null ? "KMS" : "AES256"
    kms_key         = var.kms_key_arn
  }

  tags = {
    Name = "sparc-auditor-ecr"
  }
}

resource "aws_ecr_lifecycle_policy" "auditor" {
  repository = aws_ecr_repository.auditor.name

  policy = local.ecr_lifecycle_policy[var.tagged_retain_count]
}

# ---------------------------------------------------------------------------
# ENHANCED registry scanning (#635)
#
# The per-repository `scan_on_push = true` above had never produced a single
# scan result on any of the six repositories. Our images are published as OCI
# image indexes (application/vnd.oci.image.index.v1+json) and BASIC scanning
# does not scan manifest lists — so the setting was an unconditional no-op.
# It still read as a satisfied control everywhere it was inspected: terraform
# declared it, the ECR API returned scanOnPush=true, and only asking for
# findings (ScanNotFoundException) revealed there were none.
#
# ENHANCED scanning is Inspector-backed: it scans the child platform manifests
# of an index, and CONTINUOUS_SCAN re-evaluates already-pushed images as new
# CVEs are published — the continuous-monitoring half of RA-5 that scan-on-push
# cannot provide even when it works.
#
# Registry scanning configuration is an ACCOUNT-LEVEL SINGLETON, not a
# per-repository setting. This module is instantiated exactly once
# (AWS/ECS/main.tf), so these resources live here beside the repositories they
# govern; do not add a second module instantiation without moving them.
#
# Gated (default false) because Inspector bills per image scan and per rescan.
#
# PORTABILITY — leave this false if Inspector is not available to you:
#   * AWS Organizations delegated administration. Inspector is usually managed
#     centrally by a security account; a member account frequently cannot
#     self-enable, and this resource then FAILS AT APPLY rather than degrading.
#     If your org has a delegated admin, let it own scanning and keep this off.
#   * SCPs denying inspector2:* in workload accounts.
#   * Partition/region availability — Inspector v2 is not everywhere, and
#     air-gapped partitions are the sharpest case.
#   * Cost.
#
# With this false the stack applies cleanly — but `scan_on_push` above is then
# still inert for image indexes, so it is NOT your scanning control. Scan out of
# band instead (SBOM + grype/trivy on a schedule), which is registry- and
# cloud-agnostic and works where Inspector does not. See AWS/ECS/README.md
# "Container image scanning".
# ---------------------------------------------------------------------------

resource "aws_inspector2_enabler" "ecr" {
  count = var.enable_enhanced_scanning ? 1 : 0

  account_ids    = [data.aws_caller_identity.current.account_id]
  resource_types = ["ECR"]
}

resource "aws_ecr_registry_scanning_configuration" "main" {
  count = var.enable_enhanced_scanning ? 1 : 0

  scan_type = "ENHANCED"

  rule {
    scan_frequency = "CONTINUOUS_SCAN"

    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }

  # ENHANCED cannot be set until Inspector is enabled for the ECR resource
  # type — the API rejects it otherwise.
  depends_on = [aws_inspector2_enabler.ecr]
}
