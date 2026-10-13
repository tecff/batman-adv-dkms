# Build environment for the batman-adv-dkms Debian source package.
#
# Contains ONLY the packaging toolchain — no kernel headers, no compiler —
# because the package is Architecture: all (sources only; DKMS compiles on the
# target host, not here). Pinning the toolchain in an image means builds survive
# build-host reinstalls and stay reproducible.
#
# The repo is bind-mounted at run time (see Jenkinsfile), so this image carries
# no source and is reused across builds/versions.
FROM debian:bookworm-slim

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        dpkg-dev \
        debhelper \
        dh-dkms \
        git \
        xz-utils \
        ca-certificates && \
    rm -rf /var/lib/apt/lists/*
# Note: build-essential (gcc/g++/make) is NOT used to compile anything — the
# package is Architecture: all (sources only; DKMS compiles on the target).
# But dpkg-buildpackage injects build-essential as an implicit Build-Depends
# and dpkg-checkbuilddeps rejects the build without it. Keep it to satisfy the
# checker; do NOT remove even though no compilation happens here.

# Match the suite the package targets. Bump this when moving to trixie+.
LABEL org.opencontainers.image.title="batman-adv-dkms builder" \
      org.opencontainers.image.description="Packaging toolchain for the tecff batman-adv-dkms source package" \
      org.techff.base="debian:bookworm-slim"

WORKDIR /workspace
CMD ["./build.sh"]
