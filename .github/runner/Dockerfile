# ===========================================================================
# SPARC CI Runner — Pre-built container for GitHub Actions
# ===========================================================================
# All CI tools pre-installed for deterministic, fast pipeline execution.
# Eliminates per-run tool installs (~90-120s savings per run).
#
# Build:  docker build -t sparc-ci-runner .
# Test:   docker run --rm sparc-ci-runner terraform version
#
# Tool versions pinned for reproducibility. Update versions here,
# rebuild, and all workflows pick up changes automatically.
# ===========================================================================

FROM python:3.12-slim AS base

# Versions — single source of truth
ENV TERRAFORM_VERSION=1.9.8 \
    TRUFFLEHOG_VERSION=3.94.2 \
    SAF_CLI_VERSION=1.5.3 \
    NODE_MAJOR=22 \
    CHECKOV_VERSION=3.2.506 \
    SEMGREP_VERSION=1.157.0 \
    PIP_AUDIT_VERSION=2.10.0 \
    MATPLOTLIB_VERSION=3.10.8 \
    AWS_CLI_VERSION=2 \
    GH_CLI_VERSION=latest \
    OSCAL_CLI_VERSION=1.0.3

# ---------------------------------------------------------------------------
# System dependencies
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    git \
    jq \
    gnupg \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Node.js 22 (for SAF CLI)
# ---------------------------------------------------------------------------
RUN curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR}.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Terraform
# ---------------------------------------------------------------------------
RUN curl -sSfL "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" \
    -o /tmp/terraform.zip \
    && unzip /tmp/terraform.zip -d /usr/local/bin/ \
    && rm /tmp/terraform.zip \
    && terraform version

# ---------------------------------------------------------------------------
# TruffleHog (native binary — no Docker-in-Docker)
# ---------------------------------------------------------------------------
RUN curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
    | sh -s -- -b /usr/local/bin "v${TRUFFLEHOG_VERSION}" \
    && trufflehog --version

# ---------------------------------------------------------------------------
# Python security & compliance tools
# Installed separately to avoid tomli version conflict between
# semgrep (~=2.0.1) and pip-audit (>=2.2.1)
# ---------------------------------------------------------------------------
RUN pip install --no-cache-dir \
    checkov==${CHECKOV_VERSION} \
    matplotlib==${MATPLOTLIB_VERSION} \
    "pyyaml>=6.0" \
    "openpyxl>=3.1"

RUN pip install --no-cache-dir semgrep==${SEMGREP_VERSION}

RUN pip install --no-cache-dir pip-audit==${PIP_AUDIT_VERSION}

# ---------------------------------------------------------------------------
# SAF CLI (MITRE Security Automation Framework)
# ---------------------------------------------------------------------------
RUN npm install -g "@mitre/saf@${SAF_CLI_VERSION}" \
    && saf --version

# ---------------------------------------------------------------------------
# AWS CLI v2
# ---------------------------------------------------------------------------
RUN curl -sSf "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
    -o /tmp/awscli.zip \
    && unzip -q /tmp/awscli.zip -d /tmp/ \
    && /tmp/aws/install \
    && rm -rf /tmp/awscli.zip /tmp/aws \
    && aws --version

# ---------------------------------------------------------------------------
# GitHub CLI
# ---------------------------------------------------------------------------
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# ---------------------------------------------------------------------------
# Java 21 + oscal-cli (OSCAL schema + constraint validation)
# Built from source — no pre-built binaries are published.
# ---------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    default-jdk-headless \
    maven \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 --branch "v${OSCAL_CLI_VERSION}" \
      https://github.com/usnistgov/oscal-cli.git /tmp/oscal-cli-src \
    && cd /tmp/oscal-cli-src \
    && mvn package -DskipTests -q -batch-mode \
    && mkdir -p /opt/oscal-cli \
    && cp -a "target/cli-core-${OSCAL_CLI_VERSION}-oscal-cli/." /opt/oscal-cli/ \
    && chmod +x /opt/oscal-cli/bin/oscal-cli \
    && ln -s /opt/oscal-cli/bin/oscal-cli /usr/local/bin/oscal-cli \
    && cd / && rm -rf /tmp/oscal-cli-src \
    && oscal-cli --version

# ---------------------------------------------------------------------------
# cosign (image signing verification)
# ---------------------------------------------------------------------------
ENV COSIGN_VERSION=3.0.5
RUN curl -sSfL "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-amd64" \
    -o /usr/local/bin/cosign \
    && chmod +x /usr/local/bin/cosign

# ---------------------------------------------------------------------------
# Git config for CI commits
# ---------------------------------------------------------------------------
RUN git config --system user.name "github-actions[bot]" \
    && git config --system user.email "github-actions[bot]@users.noreply.github.com" \
    && git config --system --add safe.directory /github/workspace \
    && git config --system --add safe.directory '*'

# ---------------------------------------------------------------------------
# Verify all tools
# ---------------------------------------------------------------------------
RUN echo "=== Tool Versions ===" \
    && python3 --version \
    && terraform version \
    && node --version \
    && npm --version \
    && saf --version \
    && checkov --version \
    && semgrep --version \
    && pip-audit --version \
    && trufflehog --version \
    && aws --version \
    && gh --version \
    && cosign version \
    && oscal-cli --version \
    && echo "=== All tools verified ==="

WORKDIR /github/workspace
