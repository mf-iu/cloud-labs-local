# Dev container image for the labs of the cloud computing course: every
# tool except the CLI of a cloud provider. devcontainer.json adds Docker,
# kubectl, Helm and the GitHub CLI as dev container features on top of this
# image. The provider repositories build this same Dockerfile from their own
# devcontainer.json and add their CLI there.
FROM mcr.microsoft.com/devcontainers/base:3-noble

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive

# Versions of the tools that come from GitHub releases
ARG K3D_VERSION=v5.8.3
ARG PMTILES_VERSION=1.31.2
ARG TRIVY_VERSION=0.74.0
ARG TRIVY_SHA256_AMD64=2ae6fe3ee734b7fdf11335663e18c75ea12dccc76062f09f164a3b0f8be4371a
ARG TRIVY_SHA256_ARM64=b94ce1976bbf3c15b514b605ee88be7c6d94a29be2302847ff01cb794d47aad5
ARG SYFT_VERSION=1.54.0
ARG SYFT_SHA256_AMD64=54a87372498168b2d033e876fd41fa4e8035b872699e525a57046e1f2f09c860
ARG SYFT_SHA256_ARM64=ee6d4566373a05b344bc6b5f1706f14419bf9338ba39ff686e247deefe9b8818
ARG COSIGN_VERSION=3.1.3
ARG COSIGN_SHA256_AMD64=4629c757b7618056f8ddd7e2625ae9fdd94c0372a65049520bc7d9df9efc7f71
ARG COSIGN_SHA256_ARM64=c5d324e091826b0d7a78eb16fef316450b4eb9aaec045611c08ba06f5e73220a

# Ubuntu packages: Python 3.12, network diagnosis (T04), OpenStreetMap tools (T06),
# shell tools
# hadolint ignore=DL3008
RUN apt-get update \
 && apt-get install --yes --no-install-recommends \
      python3 python3-pip gnupg \
      dnsutils iputils-ping netcat-openbsd tcpdump traceroute openssh-client openssl \
      osm2pgsql osmium-tool \
      jq zip unzip shellcheck \
 && rm --recursive --force /var/lib/apt/lists/*

# psql 18 (T06) from the package repository of PostgreSQL
# hadolint ignore=DL3008
RUN install --directory /usr/share/postgresql-common/pgdg \
 && curl --fail --silent --show-error --location --output /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
      https://www.postgresql.org/media/keys/ACCC4CF8.asc \
 && echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc]" \
      "https://apt.postgresql.org/pub/repos/apt noble-pgdg main" >/etc/apt/sources.list.d/pgdg.list \
 && apt-get update \
 && apt-get install --yes --no-install-recommends postgresql-client-18 \
 && rm --recursive --force /var/lib/apt/lists/*

# OpenTofu (T08) from its Debian package repository
RUN curl --fail --silent --show-error --location --output /tmp/install-opentofu.sh https://get.opentofu.org/install-opentofu.sh \
 && sh /tmp/install-opentofu.sh --install-method deb \
 && rm --recursive --force /tmp/install-opentofu.sh /var/lib/apt/lists/*

# uv manages Python versions, virtual environments and packages
COPY --from=ghcr.io/astral-sh/uv:0.12 /uv /uvx /usr/local/bin/

# k3d runs a Kubernetes cluster in Docker (T03); pmtiles cuts map tiles (T07)
RUN arch="$(dpkg --print-architecture)" \
 && curl --fail --silent --show-error --location --output /usr/local/bin/k3d \
      "https://github.com/k3d-io/k3d/releases/download/${K3D_VERSION}/k3d-linux-${arch}" \
 && chmod 755 /usr/local/bin/k3d \
 && if [ "$arch" = amd64 ]; then parch=x86_64; else parch="$arch"; fi \
 && curl --fail --silent --show-error --location "https://github.com/protomaps/go-pmtiles/releases/download/v${PMTILES_VERSION}/go-pmtiles_${PMTILES_VERSION}_Linux_${parch}.tar.gz" \
    | tar --extract --gzip --directory /usr/local/bin pmtiles

# Trivy scans container images for vulnerabilities (T02). Pinned version with
# checksum: some releases and images were compromised in March 2026.
RUN case "$(dpkg --print-architecture)" in \
      amd64) tarch=64bit; sum="$TRIVY_SHA256_AMD64" ;; \
      arm64) tarch=ARM64; sum="$TRIVY_SHA256_ARM64" ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac \
 && curl --fail --silent --show-error --location --output /tmp/trivy.tar.gz \
      "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VERSION}/trivy_${TRIVY_VERSION}_Linux-${tarch}.tar.gz" \
 && echo "$sum  /tmp/trivy.tar.gz" | sha256sum --check - \
 && tar --extract --gzip --file /tmp/trivy.tar.gz --directory /usr/local/bin trivy \
 && rm /tmp/trivy.tar.gz

# Syft lists the packages of an image (Software Bill of Materials, SBOM), cosign
# signs and verifies images (T02, T08). Pinned versions with checksums, like
# Trivy.
RUN arch="$(dpkg --print-architecture)" \
 && case "$arch" in \
      amd64) syft_sum="$SYFT_SHA256_AMD64"; cosign_sum="$COSIGN_SHA256_AMD64" ;; \
      arm64) syft_sum="$SYFT_SHA256_ARM64"; cosign_sum="$COSIGN_SHA256_ARM64" ;; \
      *) echo "unsupported architecture" >&2; exit 1 ;; \
    esac \
 && curl --fail --silent --show-error --location --output /tmp/syft.tar.gz \
      "https://github.com/anchore/syft/releases/download/v${SYFT_VERSION}/syft_${SYFT_VERSION}_linux_${arch}.tar.gz" \
 && echo "$syft_sum  /tmp/syft.tar.gz" | sha256sum --check - \
 && tar --extract --gzip --file /tmp/syft.tar.gz --directory /usr/local/bin syft \
 && curl --fail --silent --show-error --location --output /usr/local/bin/cosign \
      "https://github.com/sigstore/cosign/releases/download/v${COSIGN_VERSION}/cosign-linux-${arch}" \
 && echo "$cosign_sum  /usr/local/bin/cosign" | sha256sum --check - \
 && chmod 755 /usr/local/bin/cosign \
 && rm /tmp/syft.tar.gz

# Mount point for the SSH keys of Windows Subsystem for Linux (WSL) and the
# parent of further mount points (see devcontainer.json), owned by the container
# user, so that Docker does not create them as root
RUN install --directory --owner vscode --group vscode /home/vscode/.ssh /home/vscode/.config
