# batman-adv-dkms

Debian packaging for the [batman-adv](https://www.open-mesh.org/) kernel module,
delivered as a **DKMS source package**. DKMS compiles the module automatically
whenever a new kernel image is installed, so the module no longer has to be
rebuilt by hand for each kernel release. This replaces the legacy
`tecff/scripts/build-batman_adv` script.

**Read [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) for the full rationale** —
host roles, the end-to-end pipeline, comparison with the old script and with
other Freifunk communities, distribution, monitoring, and the in-kernel-module
alternative. This README is the quick how-to.

## Host roles

| | Build host (you provide) | Target host = host03.tecff.de |
|---|---|---|
| Purpose | Builds the source `.deb` | Compiles the module via DKMS |
| Needs | `dpkg-dev debhelper dh-dkms git xz-utils devscripts` | `dkms linux-headers-$(uname -r)` (pulls gcc/make/etc.) |
| Does **not** need | kernel headers, gcc, the target kernel | dpkg-dev, debhelper, dh-dkms, git, quilt, checkinstall |
| Footprint | packaging toolchain (~build host only) | compiler slice only (~150–250 MB) |

Nothing is compiled on the build host (the package is `Architecture: all`).
DKMS *is* "compile on the target", so the target irreducibly needs a compiler —
but no packaging tools.

## Layout

```
.
├── build.sh                       # build driver (prepare / build / source / clean / all)
├── docs/ARCHITECTURE.md           # full rationale & pipeline
└── debian/
    ├── changelog                  # single source of truth for the version
    ├── control                    # Source/binary metadata; Architecture: all
    ├── copyright
    ├── rules                      # dh --with dkms; stages sources to usr/src/
    ├── batman-adv-dkms.dkms       # dkms.conf template (AUTOINSTALL, -j, KERNELPATH)
    ├── source/format              # 3.0 (quilt)
    └── patches/series             # add quilt patches here when needed
```

Upstream sources are vendored at build time (cloned from
`https://git.open-mesh.org/batman-adv.git` at tag `v<upstream-version>`) into a
reproducible `orig.tar.xz`, so the `.dsc`/`.deb` is self-contained.

## Build (on the build host)

```
apt install dpkg-dev debhelper dh-dkms git xz-utils devscripts   # once
./build.sh            # prepare + build binary .deb (default = "all")
./build.sh source     # produce .dsc + orig.tar.xz + debian.tar.xz
./build.sh clean      # wipe build/
```
Artifacts appear in `build/`.

## Continuous Integration (Jenkins on host02.tecff.de)

Builds run in a pinned Docker toolchain image (`Dockerfile`) driven by the
`Jenkinsfile` (declarative pipeline). The image carries only the packaging
stack — no compiler, no kernel headers — so it survives build-host reinstalls
and stays reproducible. Resulting `.deb`(s) are archived to the Jenkins build;
there is no auto-publish step.

Setup (once, on host02's Jenkins):

1. Create a **Multibranch Pipeline** job pointing at this repo.
2. Branch sources → add a **Tags** source filtered to `v*` (release tags) so a
   tag push triggers a build.
3. Point a GitHub webhook at Jenkins (or schedule periodic "Scan"), so new tags
   are discovered.
4. The executor needs Docker; the `jenkins` user must be able to run
   `docker build` / `docker run` (membership in the `docker` group, or rootless
   Docker).

Local dry-run (no Jenkins needed):
```
docker build -t tecff/batman-adv-dkms-builder:bookworm .
docker run --rm -v "$PWD":/workspace -w /workspace tecff/batman-adv-dkms-builder:bookworm ./build.sh
```

## Bump to a new batman-adv release

1. `dch -v 2026.1-1~tecff1`  (adds a `debian/changelog` entry — the only file
   you edit by hand; it is the single source of truth).
2. `./build.sh` — derives git tag `v2026.1`, re-syncs `PACKAGE_VERSION` in the
   `.dkms` file, fetches upstream, builds the `.deb`.

## Deploy on the target host (host03.tecff.de)

Simplest (single server):
```
scp build/batman-adv-dkms_2026.2-1~tecff1_all.deb root@host03.tecff.de:/tmp/
ssh root@host03.tecff.de 'apt install -y /tmp/batman-adv-dkms_2026.2-1~tecff1_all.deb'
```
Or publish to a tiny apt repo on host03 (which already serves HTTP) and
`apt install batman-adv-dkms` — see `docs/ARCHITECTURE.md` §8.

Install registers the module with DKMS and builds it for the running kernel.
Future `apt upgrade` of `linux-image-amd64` rebuild it automatically
(`AUTOINSTALL=yes`). Inspect:
```
dkms status        # batman-adv/2026.2: installed   (or failed — see §9)
modinfo batman-adv
```
Remove: `apt remove batman-adv-dkms` (also runs `dkms remove --all`).

## Patches & config flags

- **Patches:** drop quilt patches into `debian/patches/`, list in
  `debian/patches/series` (supersedes `/usr/src/batman_adv_patches/` + `git am`).
- **Config knobs** (`CONFIG_BATMAN_ADV_DEBUG`, `_BLA`, `_DAT`, `_NC`, `_MCAST`):
  append to `MAKE[0]` in `debian/batman-adv-dkms.dkms` — documented there. This
  is where you enable the deprecated DEBUGFS/SYSFS interfaces the old script
  mentioned.

## Monitoring

If a new kernel breaks the build (API change between batman-adv releases),
`dkms status` shows `failed` — silent otherwise. Add a healthcheck; see
`docs/ARCHITECTURE.md` §9.
