// Declarative pipeline for the batman-adv-dkms package.
//
// Produces the binary .deb inside a pinned Docker toolchain image (see
// Dockerfile) and archives it to the Jenkins build. No publication step —
// download the .deb from the build page when you want to deploy it.
//
// Recommended setup on host02's Jenkins:
//   * Job type: "Multibranch Pipeline" pointing at this repo.
//   * Under "Branch sources" → add a "Tags" source with filter `v*` (or
//     `\d+\.\d+\.`) so pushing/updating a release tag triggers a build.
//   * Enable GitHub webhook (or schedule periodic "Scan Multibranch Pipeline")
//     so new tags are discovered automatically.
//   * The executor node needs Docker, and the jenkins user must be allowed to
//     run `docker build` / `docker run` (typically membership in the `docker`
//     group, or rootless Docker).
//   * Adjust `agent {}` below if your executors use a specific label.
//
// Why Docker: the toolchain (dpkg-dev, debhelper, dh-dkms, ...) is baked into
// the image, so a build-host wipe or OS upgrade can't silently break builds —

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
                // Run as the jenkins UID/GID so artifacts are owned by the
                // jenkins user (lets the post-step `rm -rf build` succeed and
                // keeps the workspace tidy without root-owned leftovers).
                sh '''
                    set -e
                    mkdir -p build
                    docker run --rm \
                        --user "$(id -u):$(id -g)" \
                        --env HOME=/tmp \
                        -v "$PWD":/workspace \
                        -w /workspace \
                        "$IMAGE_TAG" \
                        ./build.sh
                '''
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
