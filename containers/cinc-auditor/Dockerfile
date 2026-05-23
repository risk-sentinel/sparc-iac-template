# =============================================================================
# risksentinel/cinc-auditor — custom cinc-auditor image (sparc-iac#229)
# =============================================================================
# Built from cincproject/workstation (NOT cincproject/auditor) so future
# Ohai-using profiles can extend without rebasing the consumer story.
# Workstation includes cinc-auditor, knife, and ohai bundled together.
#
# 20 gems baked in (19 aws-sdk + pg) per the comprehensive list in #229.
# Initial rs1 manifest (11 gems) driven by sparc-validate#79's Phase B +
# Phase B+ audit of `require "aws-sdk-*"` calls. rs2 (2026-05-11) adds 9
# gems — Tier 1 (accessanalyzer) + Tier 2 (inspector2 / pi / backup) +
# Tier 3 (macie2 / wafv2 / resourcegroupstaggingapi / auditmanager /
# detective) — per #229's 2026-05-11 comment from a fresh probe against
# the live image plus sparc-validate's expanded custom-resource set.
#
# Architecture: linux/amd64 only. The cincproject/workstation:26.0.1 base
# does not publish a linux/arm64/v8 variant on Docker Hub (verified
# 2026-05-08). Adopters running this image on ARM64 hosts (e.g., Graviton)
# need to run with x86 emulation OR fall back to host-installed
# cinc-auditor. sparc-iac's db_scanner_runner (currently t4g.small Graviton)
# is unaffected — it host-installs via dpkg, doesn't consume this image.
#
# See docs/dev/cinc_image_pinning.md for the full pinning policy and the
# image-tag → workstation-base → auditor-version → ohai-version mapping.
# =============================================================================

# Pinned by digest for FedRAMP-grade reproducibility (#229 + sparc-validate#26
# image-pinning policy). Bump deliberately; update docs/dev/cinc_image_pinning.md
# version-mapping table in the same commit.
FROM cincproject/workstation@sha256:970d1f69bc9b49c82aac0b2e9ad742d053b81eda96f288a52662c7c6b49a07fa

# -----------------------------------------------------------------------------
# 1. OS-level CA store (cinc-workstation is Debian-based; uses
#    /usr/local/share/ca-certificates + update-ca-certificates).
#    Drop your internal CA cert(s) into the `certs/` directory next to this
#    Dockerfile. Empty by default — no-op for non-corporate builds.
# -----------------------------------------------------------------------------
COPY certs/ /usr/local/share/ca-certificates/
RUN update-ca-certificates

# -----------------------------------------------------------------------------
# 2. Ruby / AWS SDK SSL trust. Make explicit so the AWS SDK,
#    cinc-auditor's HTTP calls, and `gem install` all use the same store.
# -----------------------------------------------------------------------------
ENV SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
ENV SSL_CERT_DIR=/etc/ssl/certs

# -----------------------------------------------------------------------------
# 3. (Optional) Corporate egress proxy — uncomment + customize per your
#    network. NO_PROXY should at minimum cover localhost + the EC2 IMDS
#    endpoint (169.254.169.254) so AWS SDK metadata calls stay direct.
# -----------------------------------------------------------------------------
# ENV HTTP_PROXY=http://proxy.internal.corp:8080
# ENV HTTPS_PROXY=http://proxy.internal.corp:8080
# ENV NO_PROXY=localhost,127.0.0.1,169.254.169.254,.internal

# -----------------------------------------------------------------------------
# 4. (Optional) Private gem mirror. Use --source to bypass rubygems.org,
#    or copy a pre-configured /root/.gemrc earlier in the build.
# -----------------------------------------------------------------------------
# RUN /opt/cinc-workstation/embedded/bin/gem install --no-document \
#       --source https://gems.internal.corp/ \
#       aws-sdk-workspacesweb ...

# -----------------------------------------------------------------------------
# 5. Bake the missing gems into cinc-workstation's bundled Ruby.
#    19 aws-sdk-* gems missing from the workstation base image plus pg.
#    Source list maintained in docs/dev/cinc_image_pinning.md §"Gem manifest".
#    Groupings below mirror the manifest's tier structure:
#      - rs1 manifest (10 gems): Phase B end-user-compute + compute + database
#      - rs2 Tier 1 (1 gem): access-analyzer for cis-aws-foundations C-2.18
#      - rs2 Tier 2 (3 gems): inspector2 + pi + backup for ECS/ECR/RDS deep-dive
#      - rs2 Tier 3 (5 gems): adjacent compliance evidence (macie2 / wafv2 /
#                              resourcegroupstaggingapi / auditmanager / detective)
# -----------------------------------------------------------------------------
RUN /opt/cinc-workstation/embedded/bin/gem install --no-document \
    aws-sdk-workspacesweb aws-sdk-workdocs aws-sdk-appstream \
    aws-sdk-lightsail aws-sdk-apprunner aws-sdk-simspaceweaver \
    aws-sdk-memorydb aws-sdk-keyspaces aws-sdk-timestreamwrite \
    aws-sdk-workspaces \
    aws-sdk-accessanalyzer \
    aws-sdk-inspector2 aws-sdk-pi aws-sdk-backup \
    aws-sdk-macie2 aws-sdk-wafv2 aws-sdk-resourcegroupstaggingapi \
    aws-sdk-auditmanager aws-sdk-detective \
    pg

ENTRYPOINT ["cinc-auditor"]
