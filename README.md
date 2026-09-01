# Core Lightning Docker image

This repository packages official Core Lightning release binaries into a
multi-architecture Docker image for Umbrel.

It does **not** compile Core Lightning from source. For security releases where
source code is temporarily embargoed, the image is assembled from the binaries
covered by Core Lightning's signed release manifests.

## Verification

The Docker build performs the following checks before copying any Core
Lightning files into the final image:

1. Imports the public key committed in [`keys/ngoline.asc`](keys/ngoline.asc).
2. Confirms that it contains the expected primary-key fingerprint
   `A57656F8004F6FD68ED99C85BE277A87802A6F08` and signing-subkey fingerprint
   `4E4A142F8BD3C38A56B362ED578CAC08472545C5`.
3. Downloads the architecture-specific checksum manifest and detached signature
   from the upstream GitHub release.
4. Requires a valid, unexpired, and unrevoked signature from that exact
   fingerprint.
5. Verifies the selected Ubuntu 22.04 release tarball against the signed
   checksum manifest.
6. Independently verifies the tarball against the reviewed hash pinned in the
   Dockerfile.

The vendored key includes the signer's current self-certification from
[keys.openpgp.org][signing-key]. Its primary and signing-subkey fingerprints
must be reviewed whenever the key is refreshed. Because the key is vendored,
the build can only detect a revocation that has been incorporated into this
file; checking for upstream key updates remains part of each release review.

As in Core Lightning's corrected upstream Docker image, executable ELF files
are stripped after verification to reduce the final image size. No source code
is compiled and no executable content is added to the CLN binaries.

The image supports `linux/amd64` and `linux/arm64`. It also includes Bitcoin
Core's `bitcoin-cli` v27.1 for compatibility with the upstream CLN image. Its
architecture-specific checksums are pinned in the Dockerfile from Bitcoin
Core's official v27.1 checksum manifest.

## Core Lightning v26.06.7

Core Lightning initially published Docker images tagged `v26.06.7` that
reported the new version but did not contain its security fixes. Those images
were generated from a placeholder tag and were later replaced upstream.

This repository packages the corrected, signed `v26.06.7` release tarballs
documented in the [Core Lightning v26.06.7 release notes][cln-release].

## Build locally

```sh
set -a
source versions.env
set +a

docker buildx build \
  --platform linux/amd64 \
  --build-arg "CLN_VERSION=${CLN_VERSION}" \
  --build-arg "BITCOIN_VERSION=${BITCOIN_VERSION}" \
  --load \
  --tag core-lightning:test \
  .

docker run --rm --entrypoint lightningd core-lightning:test --version
```

Use the host's native platform for a locally loaded image. The GitHub workflow
tests amd64 and arm64 independently.

## Publish

Images are published only from Git tags matching the exact `IMAGE_VERSION` in
[`versions.env`](versions.env). The tagged commit must already be contained in
`master`. Version tags include an Umbrel packaging revision; this repository
intentionally does not publish `latest`.

For example:

```sh
git tag v26.06.7-umbrel.1
git push origin v26.06.7-umbrel.1
```

The workflow publishes:

```text
ghcr.io/getumbrel/docker-core-lightning:v26.06.7-umbrel.1
```

The workflow builds and tests amd64 and arm64 independently on native runners.
For a release, those exact tested images are exported as workflow artifacts and
assembled into the multi-architecture manifest without rebuilding them under
emulation.

Before publishing, configure these repository protections:

1. Protect the `v*-umbrel.*` tag namespace with a GitHub ruleset that restricts
   tag creation to maintainers.
2. Add required reviewers to the `release` Actions environment used by the
   publish job.
3. Keep `master` protected and require the test job to pass before merge.

The workflow serializes publication of each release tag, fails closed when it
cannot establish that the GHCR tag is unused, and refuses to replace an
existing tag. GHCR does not provide truly immutable tags, so Umbrel packages
must always pin the published manifest digest.

On the first publication, GitHub may create the GHCR package as private. The
workflow will publish commit-specific staging images but stop before creating
the release manifest if they cannot be read anonymously. Set the package
visibility to public and rerun the publish job. The completed workflow verifies
anonymous access to both architectures and writes the final manifest digest to
the job summary.

After publishing, pin the multi-architecture manifest digest—not an
architecture-specific child digest—in the Umbrel app package.

[cln-release]: https://github.com/ElementsProject/lightning/releases/tag/v26.06.7
[signing-key]: https://keys.openpgp.org/vks/v1/by-fingerprint/A57656F8004F6FD68ED99C85BE277A87802A6F08
