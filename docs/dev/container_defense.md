# Container Scanning and Control Coverage

Trivy + Grype + Snyk + Prisma Cloud Defender – Combined NIST SP 800-53 Rev. 5 Coverage

## Control Coverage (needs review)

| NIST Control | Specific Part / Enhancement | Description | **Trivy** | **Grype** | **Snyk** | **Prisma Defender** | **Combined (All Tools)** | Overall Coverage |
| ------------ | --------------------------- | ----------- | --------- | --------- | -------- | ------------------- | ------------------------ | ---------------- |
| **RA-5** | RA-5 (base) | Vulnerability monitoring & scanning | **Full** (static + SBOM) | **Full** (vuln-focused + SBOM via Syft) | **Full** (strong SCA + container) | **Full + Enhanced** (static + runtime) | **Full + Enhanced** | Excellent |
| **RA-5** | RA-5(2) | Frequency & update of vuln scanning | **Full** | **Full** | **Full** | **Full + Enhanced** | **Full + Enhanced** | Excellent |
| **RA-5** | RA-5(3) | Breadth / depth of coverage | **Partial** | **Partial** (vuln-only) | **Full** (code + IaC + deps) | **Full** | **Full** | Excellent |
| **RA-5** | RA-5(5) | Privileged access scanning | **Partial** | **None** | **Partial** | **Full** (runtime) | **Full** | Excellent |
| **RA-5** | RA-5(11) | Public repositories scanning | **Full** | **Full** | **Full** | **Full** | **Full** | Excellent |
| **CM-2** | CM-2 (base) + (1) | Baseline configuration | **Full** (misconfig) | **None** | **Full** (IaC + config) | **Full + Enhanced** | **Full + Enhanced** | Excellent |
| **CM-6** | CM-6 (base) + (1) | Configuration settings | **Full** | **None** | **Full** | **Full + Enhanced** | **Full + Enhanced** | Excellent |
| **CM-6** | CM-6(3) | Unauthorized change / drift detection | **None** | **None** | **Partial** (limited) | **Full** (runtime) | **Full** | Excellent |
| **CM-7** | CM-7 (base) + (1)(2) | Least functionality | **Partial** | **None** | **Partial** | **Full** (runtime) | **Full** | Excellent |
| **SI-2** | SI-2 (base) | Flaw remediation | **Full** | **Full** | **Full** | **Full + Enhanced** | **Full + Enhanced** | Excellent |
| **SI-3** | SI-3 (base) + (1)(2)(3) | Malicious code protection | **None** | **None** | **Partial** (some malware intel) | **Full** (WildFire + runtime) | **Full** | Excellent |
| **SI-4** | SI-4 (base) + (1)(4) | System monitoring & comms | **Partial** | **None** | **Partial** | **Full** (runtime) | **Full** | Excellent |
| **SI-7** | SI-7 (base) | Software / info integrity | **Partial** | **Partial** (via SBOM) | **Partial** | **Full** (runtime drift) | **Full** | Excellent |
| **IA-5** | IA-5(7) | No embedded unencrypted authenticators | **Full** (secrets) | **None** | **Full** (secrets) | **Full** | **Full** | Excellent |
| **AC-6** | AC-6 (base) + (9)(10) | Least privilege | **Partial** | **None** | **Partial** | **Full** (runtime) | **Full** | Excellent |
| **SA-11** | SA-11 (base) + (1)(2) | Developer testing & evaluation | **Full** | **Full** (vuln + SBOM) | **Full** (dev-first SCA) | **Full + Enhanced** | **Full + Enhanced** | Excellent |
| **SR-4 / SR-5** | Supply chain risk & provenance | Component inventory & risk | **Full** (SBOM) | **Full** (Syft + Grype) | **Full** (strong SCA) | **Full + Enhanced** | **Full + Enhanced** | Excellent |
| **CM-10** | CM-10 | Software usage / license restrictions | **Full** (license) | **None** (Grant companion) | **Full** | **Full** | **Full** | Excellent |
| **CA-7** | CA-7 (base) | Continuous monitoring | **Partial** (CI/CD) | **Partial** | **Full** (platform) | **Full** (runtime) | **Full** | Excellent |
| **IR-4** | IR-4 | Incident handling & response | **None** | **None** | **Partial** | **Full** (auto containment) | **Full** | Excellent |

**Legend**:

- **Full** = Strong direct evidence / capability
- **Partial** = Good but incomplete (mostly static)
- **None** = Not provided
- **Full + Enhanced** = Best possible (static + runtime prevention, blocking, automation)

### Key Insights on the Tools

- **Trivy**: Broadest open-source coverage (vuln + misconfig + secrets + license + IaC + K8s).
- **Grype** (Anchore): Excellent pure vulnerability + SBOM scanning (pairs with Syft); lighter on misconfigs/secrets.
- **Snyk**: Developer-centric with strong SCA, IaC, secrets, and code scanning; limited runtime protection.
- **Prisma Cloud Defender**: Full CWPP with runtime malware, drift detection, blocking, and automated container kill/respawn.

### HDF Output Value (High for ATO / cATO)

All four tools support exporting results in **HDF (Heimdall Data Format)** or compatible formats (JSON, SARIF, CycloneDX).  
**Combined HDF ingestion** into tools like Heimdall, Tenable.io, or custom dashboards provides:

- Automated, consolidated evidence packages for **ATO (Authority to Operate)**.
- Continuous compliance visibility toward **cATO (continuous ATO)**.
- Rich audit trails across static (shift-left) and runtime controls.
- Reduced manual evidence collection for NIST 800-53, FedRAMP, CMMC, etc.

## Recommended Strategy

Use **Trivy + Grype** in fast CI/CD pipelines (free & complementary) → **Snyk** for developer workflows → **Prisma** for runtime enforcement. Ingest everything into HDF for unified compliance reporting.

This combination delivers near-perfect NIST coverage with strong automation for authorization packages.
