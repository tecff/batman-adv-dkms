// Declarative pipeline for the batman-adv-dkms package.
//
// Produces the binary .deb inside a pinned Docker toolchain image (see
// Dockerfile) and archives it to the Jenkins build. No publication step —
// download the .deb from the build page when you want to deploy it.
//
// Recommended setup on host02's Jenkins:
//   * Job type: "Multibranch Pipeline" pointing at this repo.
//   * Default Branch source (tracks `master`) builds on EVERY push to master —
//     no extra config needed; this is the primary workflow.
//   * OPTIONAL: add a "Tags" source filtered to `v*` if you also want tagged
//     release artifacts (distinct builds attached to release tags). Purely
//     additive; skip it if every-commit coverage is enough.
//   * Enable a GitHub webhook (or schedule periodic "Scan Multibranch
//     Pipeline") so pushes/new tags are discovered automatically.
//   * The executor needs Docker configured ROOTLESS for the jenkins user (see
//     the "Rootless Docker" section in README.md). Rootless avoids granting the
//     jenkins user effective-root via the docker group, and UID-maps the
//     container's inner root to the jenkins user so bind-mounted workspace files
//     are owned correctly without an explicit --user flag.
//   * If you run Docker rootful instead, restore the --user flag noted beside
//     the "ROOTFUL fallback" comment in the Build .deb stage below.
//   * Adjust `agent {}` below if your executors use a specific label.
//
// Why Docker: the toolchain (dpkg-dev, debhelper, dh-dkms, ...) is baked into
// the image, so a build-host wipe or OS upgrade can't silently break builds.

pipeline {
    agent any

    options {
        timestamps()
        timeout(time: 15, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '25'))
    }

    environment {
        // Reusable toolchain image; rebuilt only when Dockerfile changes.
        IMAGE_TAG = 'tecff/batman-adv-dkms-builder:bookworm'
    }

    stages {

        stage('Build toolchain image') {
            steps {
                // --pull picks up base-image security updates; cheap insurance.
                sh 'docker build --pull -t "$IMAGE_TAG" .'
            }
        }

        stage('Build .deb') {
            steps {
                // Bind-mount the workspace into the container and run build.sh.
                //
                // ROOTLESS (recommended): no --user flag. The container's inner
                // root is UID-mapped to the jenkins user on the host, so files
                // written into the bind mount are owned by jenkins naturally.
                //
                // ROOTFUL fallback: uncomment the --user line below so the
                // build doesn't leave root-owned artifacts in the workspace.
                sh '''
                    set -e
                    mkdir -p build
                    docker run --rm \
                        --env HOME=/tmp \
                        -v "$PWD":/workspace \
                        -w /workspace \
                        "$IMAGE_TAG" \
                        ./build.sh
                '''
                // ROOTFUL fallback: replace the docker invocation above with:
                //   docker run --rm --user "$(id -u):$(id -g)" --env HOME=/tmp \
                //       -v "$PWD":/workspace -w /workspace "$IMAGE_TAG" ./build.sh
            }
        }

        stage('Verify artifact') {
            steps {
                sh '''
                    set -e
                    ls -lh build/*.deb
                    echo "--- control metadata ---"
                    dpkg-deb -I build/*.deb | sed -n '1,12p'
                '''
            }
        }
    }

    post {
        always {
            // Archive the .deb(s) with content hash so downloads are traceable.
            archiveArtifacts artifacts: 'build/*.deb',
                             fingerprint: true,
                             allowEmptyArchive: false
            // Clean the regenerable build dir so the workspace stays lean.
            sh 'rm -rf build'
        }
    }
}
