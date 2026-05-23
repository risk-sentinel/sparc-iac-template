# risksentinel/cinc-auditor — Custom Image Source

Custom `cinc-auditor` container image based on `cincproject/workstation` with
the 10 missing aws-sdk gems + `pg` baked in. Built from this directory and
published to Docker Hub as `risksentinel/cinc-auditor:<workstation-version>-rs<n>`.

For the **what** and **why**, see [`docs/dev/cinc_image_pinning.md`](../../docs/dev/cinc_image_pinning.md).
This README covers **how** to build, customize, and consume the image.

## Quick consume

```bash
docker pull risksentinel/cinc-auditor:26.0.1-rs1
docker run --rm risksentinel/cinc-auditor:26.0.1-rs1 --version
```

That's the consumer-facing surface. Everything below is for adopters who
fork the build (e.g., to inject corporate CAs or use a private gem mirror)
or maintainers landing a version bump.

## Building locally

```bash
cd containers/cinc-auditor

# Standard build (no customization):
docker build -t my-org/cinc-auditor:dev .

# Test the image:
docker run --rm my-org/cinc-auditor:dev --version
docker run --rm --entrypoint ohai my-org/cinc-auditor:dev --version
docker run --rm --entrypoint /opt/cinc-workstation/embedded/bin/ruby \
  my-org/cinc-auditor:dev -e \
  "require 'aws-sdk-workspacesweb'; require 'aws-sdk-workdocs'; require 'aws-sdk-appstream'; require 'aws-sdk-lightsail'; require 'aws-sdk-apprunner'; require 'aws-sdk-simspaceweaver'; require 'aws-sdk-memorydb'; require 'aws-sdk-keyspaces'; require 'aws-sdk-timestreamwrite'; require 'aws-sdk-workspaces'; require 'pg'; puts 'all-gems-loadable'"
```

## Customization for adopters

The Dockerfile is intentionally a small, readable template that fork-
adopters can extend. Three customization paths are supported out of the box:

### 1. Corporate CA certificates

Drop your `.crt` files (PEM-encoded) into `certs/` next to the Dockerfile
before running `docker build`:

```bash
cp /path/to/internal-root-ca.crt containers/cinc-auditor/certs/
cp /path/to/internal-intermediate-ca.crt containers/cinc-auditor/certs/
docker build -t my-org/cinc-auditor:internal .
```

The Dockerfile does `COPY certs/ /usr/local/share/ca-certificates/` then
runs `update-ca-certificates`, so any `.crt` files you drop will be added
to the system trust bundle. The `SSL_CERT_FILE` + `SSL_CERT_DIR` env vars
ensure the AWS SDK, cinc-auditor's HTTP calls, and `gem install` all use
the same store.

`certs/.gitkeep` keeps the directory in git but otherwise empty. **Do
not commit corporate CA certs to this repo** — keep them in your private
fork.

### 2. Corporate egress proxy

Uncomment the `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` lines in the
Dockerfile and set the values per your network:

```dockerfile
ENV HTTP_PROXY=http://proxy.internal.corp:8080
ENV HTTPS_PROXY=http://proxy.internal.corp:8080
ENV NO_PROXY=localhost,127.0.0.1,169.254.169.254,.internal
```

`NO_PROXY` should at minimum cover localhost + the EC2 IMDS endpoint
(`169.254.169.254`) so AWS SDK metadata calls stay direct.

### 3. Private gem mirror

If your environment doesn't permit pulls from rubygems.org, point the
gem-install step at your internal mirror via `--source`:

```dockerfile
RUN /opt/cinc-workstation/embedded/bin/gem install --no-document \
      --source https://gems.internal.corp/ \
      aws-sdk-workspacesweb aws-sdk-workdocs aws-sdk-appstream \
      aws-sdk-lightsail aws-sdk-apprunner aws-sdk-simspaceweaver \
      aws-sdk-memorydb aws-sdk-keyspaces aws-sdk-timestreamwrite \
      aws-sdk-workspaces pg
```

Or copy a pre-configured `/root/.gemrc` earlier in the build with your
mirror's credentials embedded.

## Architecture support

`linux/amd64` only. The `cincproject/workstation:26.0.1` base does not
publish a `linux/arm64/v8` variant on Docker Hub (verified 2026-05-08).
Adopters running this image on ARM64 hosts (e.g., AWS Graviton) need to
either run with x86 emulation (qemu-user-static) or fall back to host-
installed cinc-auditor. sparc-iac's `db_scanner_runner` (currently
t4g.small Graviton) is unaffected — it host-installs cinc-auditor via
dpkg per `AWS/ECS/modules/db_scanner_runner/user_data.sh.tftpl`, not via
this image.

## Publishing (maintainers)

Don't `docker push` from your laptop. Use the CI workflow:

1. Bump `FROM cincproject/workstation@sha256:...` in the Dockerfile to
   the new digest.
2. Update the version-mapping table in
   [`docs/dev/cinc_image_pinning.md`](../../docs/dev/cinc_image_pinning.md)
   in the same commit. Run `docker run --rm --entrypoint cinc-auditor
   <staging-image> --version` and `--entrypoint ohai <staging-image>
   --version` to capture the bundled-component versions for the table.
3. Open a PR, get review, merge.
4. Trigger `Build cinc-auditor image` workflow via GitHub Actions
   (`workflow_dispatch`) with the desired tag (e.g., `26.0.1-rs2`). The
   workflow runs the gem-load + entrypoint + ohai verifications before
   pushing to Docker Hub.
5. After publication, post the new digest in the cross-repo lockstep
   thread so sparc-validate's `Image_Pinning_Policy.md` can be updated.

## Verification step (CI)

The build workflow runs three smoke tests on every build:

- **Gem load** — `ruby -e "require 'aws-sdk-...'; ...; require 'pg'; puts 'all-gems-loadable'"`. Proves the value proposition (the gems are actually present and loadable).
- **Entrypoint** — `docker run --rm <image> --version` (uses the `cinc-auditor` ENTRYPOINT). Catches accidental ENTRYPOINT regressions; expected output is the bundled cinc-auditor version (e.g., `7.0.107` for workstation 26.0.1).
- **Ohai** — `docker run --rm --entrypoint ohai <image> --version`. Proves the workstation base's Ohai is callable, since that's the primary reason for choosing workstation over auditor.

All three must succeed for the workflow to publish.

## Related

- **#229** — issue tracking this image work + the gem manifest.
- [`docs/dev/cinc_image_pinning.md`](../../docs/dev/cinc_image_pinning.md) — pinning policy + version-mapping table.
- **sparc-validate#26** — image-pinning policy (consumer side); cross-references this repo for the auditor-version → image-tag mapping.
- **sparc-validate#79** — release-prep PR consuming these gems.
- **sparc-validate#74** — Phase 6 consumer enablement; CONSUMERS.md will direct external consumers at this image.
