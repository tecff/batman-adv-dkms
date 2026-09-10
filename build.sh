#!/usr/bin/bash
#
# Build the batman-adv-dkms Debian package.
#
#   ./build.sh prepare   fetch upstream, create orig.tar.xz, assemble build tree
#   ./build.sh build     build binary .deb(s) from the assembled tree
#   ./build.sh source    build source package (.dsc + tarballs)
#   ./build.sh clean     remove build/ artifacts
#   ./build.sh all       prepare + build  (default)
#
# The single source of truth for the version is debian/changelog (first entry).
# The upstream git tag is derived as v<upstream-version>.
# Run on a Debian host that has dpkg-dev, debhelper and dh-dkms installed.

set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REMOTE="https://git.open-mesh.org/batman-adv.git"
BUILD_DIR="${HERE}/build"

require() {
    command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }
}

parse_full_version() {
    if command -v dpkg-parsechangelog >/dev/null 2>&1; then
        dpkg-parsechangelog -S Version
    else
        # Fallback so `prepare` can run on hosts without dpkg-dev.
        head -1 "${HERE}/debian/changelog" | sed -E 's/.*\(([^)]+)\).*/\1/'
    fi
}

parse_versions() {
    FULL_VERSION="$(parse_full_version)"
    UPSTREAM_VERSION="$(printf '%s' "$FULL_VERSION" | sed 's/-[^-]*$//')"
    DEB_REVISION="$(printf '%s' "$FULL_VERSION" | sed 's/^.*-//')"
    TAG="v${UPSTREAM_VERSION}"
    : "${UPSTREAM_VERSION:?could not parse upstream version from debian/changelog}"
    echo "  full version : $FULL_VERSION"
    echo "  upstream     : $UPSTREAM_VERSION"
    echo "  debian rev   : $DEB_REVISION"
    echo "  upstream tag : $TAG"
}

sync_dkms_conf() {
    # Keep debian/batman-adv-dkms.dkms PACKAGE_VERSION aligned with the changelog.
    local f="${HERE}/debian/batman-adv-dkms.dkms"
    local cur
    cur="$(grep -E '^PACKAGE_VERSION=' "$f" | head -1 | sed -E 's/^PACKAGE_VERSION="?([^"]*)"?.*$/\1/')"
    if [[ "$cur" != "$UPSTREAM_VERSION" ]]; then
        echo "  syncing PACKAGE_VERSION in debian/batman-adv-dkms.dkms: $cur -> $UPSTREAM_VERSION"
        sed -i -E "s|^PACKAGE_VERSION=.*|PACKAGE_VERSION=\"${UPSTREAM_VERSION}\"|" "$f"
    fi
}

prepare() {
    parse_versions
    sync_dkms_conf
    require git
    require tar
    require xz
    echo ">> preparing build tree for $TAG"
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"

    local tmp_clone="${BUILD_DIR}/.upstream-clone"
    echo ">> cloning $REMOTE @ $TAG"
    git clone --quiet --depth 1 --branch "$TAG" "$REMOTE" "$tmp_clone"
    rm -rf "${tmp_clone}/.git"

    local srcdir="${BUILD_DIR}/batman-adv-dkms-${UPSTREAM_VERSION}"
    mv "$tmp_clone" "$srcdir"

    echo ">> creating reproducible orig tarball"
    tar -C "$BUILD_DIR" --sort=name --owner=0 --group=0 --numeric-owner \
        --mtime=@1735689600 -cJf \
        "${BUILD_DIR}/batman-adv-dkms_${UPSTREAM_VERSION}.orig.tar.xz" \
        "batman-adv-dkms-${UPSTREAM_VERSION}"

    echo ">> overlaying debian/"
    cp -a "${HERE}/debian" "${srcdir}/debian"

    echo ">> build tree ready: ${srcdir}"
}

run_build() {
    parse_versions
    local srcdir="${BUILD_DIR}/batman-adv-dkms-${UPSTREAM_VERSION}"
    [[ -d "$srcdir/debian" ]] || { echo "build tree missing; run '$0 prepare' first" >&2; exit 1; }
    require dpkg-buildpackage
    ( cd "$srcdir" && dpkg-buildpackage -b -uc -us )
    echo ">> artifacts in ${BUILD_DIR}/"
}

run_source() {
    parse_versions
    local srcdir="${BUILD_DIR}/batman-adv-dkms-${UPSTREAM_VERSION}"
    [[ -d "$srcdir/debian" ]] || { echo "build tree missing; run '$0 prepare' first" >&2; exit 1; }
    require dpkg-buildpackage
    ( cd "$srcdir" && dpkg-buildpackage -S -uc -us )
    echo ">> artifacts in ${BUILD_DIR}/"
}

clean() {
    rm -rf "$BUILD_DIR"
    echo ">> cleaned ${BUILD_DIR}"
}

case "${1:-all}" in
    prepare) prepare ;;
    build)   run_build ;;
    source)  run_source ;;
    clean)   clean ;;
    all)     prepare; run_build ;;
    *) echo "usage: $0 {prepare|build|source|clean|all}" >&2; exit 2 ;;
esac
