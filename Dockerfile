# The multi-architecture digest is intentionally pinned. Update it explicitly
# when refreshing the Debian base image.
ARG DEBIAN_IMAGE=debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

FROM --platform=${TARGETPLATFORM} ${DEBIAN_IMAGE} AS cln-release

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG TARGETARCH
ARG CLN_VERSION=26.06.7

RUN apt-get update && \
    apt-get install -qq -y --no-install-recommends \
        ca-certificates \
        binutils \
        curl \
        file \
        gnupg \
        xz-utils && \
    rm -rf /var/lib/apt/lists/*

COPY keys/ngoline.asc /tmp/release-keys/ngoline.asc

WORKDIR /tmp/release

RUN export GNUPGHOME=/tmp/gnupg && \
    primary_fingerprint="A57656F8004F6FD68ED99C85BE277A87802A6F08" && \
    signing_fingerprint="4E4A142F8BD3C38A56B362ED578CAC08472545C5" && \
    install -d -m 0700 "${GNUPGHOME}" && \
    gpg --batch --import /tmp/release-keys/ngoline.asc >/dev/null 2>&1 && \
    gpg --batch --with-colons --fingerprint --fingerprint | \
        awk -F: '$1 == "fpr" { print $10 }' | \
        grep -Fx "${primary_fingerprint}" >/dev/null && \
    gpg --batch --with-colons --fingerprint --fingerprint | \
        awk -F: '$1 == "fpr" { print $10 }' | \
        grep -Fx "${signing_fingerprint}" >/dev/null && \
    case "${TARGETARCH}" in \
        amd64) \
            checksum_manifest="SHA256SUMS-v${CLN_VERSION}"; \
            expected_release_sha256="53ddf124fe7058b6a2fc059d104976cc54ba5be21dc55b295cd82d01cabeb39c" \
            ;; \
        arm64) \
            checksum_manifest="SHA256SUMS-v${CLN_VERSION}-arm64"; \
            expected_release_sha256="a6e89d49468dac83122d6b795796b7f2ebb55eab6181b419f1cf9a73aeae3965" \
            ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    release_tarball="clightning-v${CLN_VERSION}-Ubuntu-22.04-${TARGETARCH}.tar.xz" && \
    release_url="https://github.com/ElementsProject/lightning/releases/download/v${CLN_VERSION}" && \
    curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
        --remote-name "${release_url}/${checksum_manifest}" && \
    curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
        --remote-name "${release_url}/${checksum_manifest}.asc" && \
    curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
        --remote-name "${release_url}/${release_tarball}" && \
    gpg_status="$(mktemp)" && \
    { gpg --batch --status-fd 3 \
        --verify "${checksum_manifest}.asc" "${checksum_manifest}" \
        3>"${gpg_status}" 2>/tmp/gpg-errors || true; } && \
    grep -F "[GNUPG:] VALIDSIG ${signing_fingerprint} " "${gpg_status}" >/dev/null && \
    ! grep -E '^\[GNUPG:\] (BADSIG|EXPKEYSIG|EXPSIG|REVKEYSIG) ' "${gpg_status}" >/dev/null && \
    test "$(grep -Fc "  ${release_tarball}" "${checksum_manifest}")" -eq 1 && \
    grep -F "  ${release_tarball}" "${checksum_manifest}" | sha256sum -c - && \
    echo "${expected_release_sha256}  ${release_tarball}" | sha256sum -c - && \
    install -d /cln && \
    tar -xJf "${release_tarball}" --no-same-owner -C /cln && \
    test -x /cln/usr/bin/lightningd && \
    test -x /cln/usr/bin/lightning-cli && \
    test -x /cln/usr/libexec/c-lightning/plugins/commando && \
    find /cln -type f -executable -exec file {} + | \
        awk -F: '/ELF/ { print $1 }' | \
        xargs -r strip --strip-unneeded && \
    rm -rf /cln/usr/share

FROM --platform=${BUILDPLATFORM} ${DEBIAN_IMAGE} AS bitcoin-release

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG TARGETARCH
ARG BITCOIN_VERSION=27.1

RUN apt-get update && \
    apt-get install -qq -y --no-install-recommends \
        ca-certificates \
        curl && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /tmp/release

# Core Lightning's upstream image includes bitcoin-cli 27.1. These checksums
# are pinned from Bitcoin Core's official 27.1 SHA256SUMS manifest.
RUN case "${TARGETARCH}" in \
        amd64) \
            bitcoin_arch="x86_64-linux-gnu"; \
            expected_sha256="c9840607d230d65f6938b81deaec0b98fe9cb14c3a41a5b13b2c05d044a48422" \
            ;; \
        arm64) \
            bitcoin_arch="aarch64-linux-gnu"; \
            expected_sha256="bb878df4f8ff8fb8acfb94207c50f959c462c39e652f507c2a2db20acc6a1eee" \
            ;; \
        *) echo "Unsupported architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac && \
    bitcoin_tarball="bitcoin-${BITCOIN_VERSION}-${bitcoin_arch}.tar.gz" && \
    curl --proto '=https' --tlsv1.2 --fail --location --show-error --silent \
        --remote-name "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/${bitcoin_tarball}" && \
    echo "${expected_sha256}  ${bitcoin_tarball}" | sha256sum -c - && \
    install -d /bitcoin && \
    tar -xzf "${bitcoin_tarball}" \
        --strip-components=2 \
        -C /bitcoin \
        "bitcoin-${BITCOIN_VERSION}/bin/bitcoin-cli" && \
    test -x /bitcoin/bitcoin-cli

FROM --platform=${TARGETPLATFORM} ${DEBIAN_IMAGE} AS final

SHELL ["/bin/bash", "-euo", "pipefail", "-c"]

ARG CLN_VERSION=26.06.7
ARG VCS_REF

LABEL org.opencontainers.image.title="Core Lightning" \
      org.opencontainers.image.description="Core Lightning packaged from upstream signed release binaries" \
      org.opencontainers.image.source="https://github.com/getumbrel/docker-core-lightning" \
      org.opencontainers.image.url="https://github.com/getumbrel/docker-core-lightning" \
      org.opencontainers.image.version="${CLN_VERSION}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      org.opencontainers.image.licenses="MIT"

RUN apt-get update && \
    apt-get install -qq -y --no-install-recommends \
        inotify-tools \
        jq \
        libpq5 \
        libsodium23 \
        libsqlite3-0 \
        socat && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/*

COPY --from=cln-release /cln/ /
COPY --from=bitcoin-release /bitcoin/bitcoin-cli /usr/bin/bitcoin-cli
COPY --chmod=755 docker-entrypoint.sh /entrypoint.sh

# v26.06.7 installs CLN under /usr. Preserve the historical /usr/local paths
# used by earlier Core Lightning Docker images and third-party integrations.
RUN mkdir -p /usr/local/libexec && \
    for binary in /usr/bin/lightning*; do \
        ln -sf "${binary}" "/usr/local/bin/$(basename "${binary}")"; \
    done && \
    ln -sf /usr/bin/reckless /usr/local/bin/reckless && \
    ln -sf /usr/libexec/c-lightning /usr/local/libexec/c-lightning

ENV LIGHTNINGD_DATA=/root/.lightning \
    LIGHTNINGD_RPC_PORT=9835 \
    LIGHTNINGD_PORT=9735 \
    LIGHTNINGD_NETWORK=bitcoin

EXPOSE 9735 9835
VOLUME ["/root/.lightning"]
ENTRYPOINT ["/entrypoint.sh"]
