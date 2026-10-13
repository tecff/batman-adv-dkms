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
//   * The executor needs Docker for the jenkins user — EITHER rootful
//     (jenkins in the docker group) OR rootless (dockerd-rootless-setuptool.sh,
//     see the "Rootless Docker" section in README.md). The pipeline probes the
//     default daemon first and falls back to the rootless socket automatically,
//     so the SAME Jenkinsfile works on both setups with no edits.
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

        stage('Pick Docker daemon') {
            steps {
                script {
                    // --- Rootless Docker support ---------------------------------------------
                    // Probe the default daemon first; fall back to the jenkins user's
                    // rootless socket if the default is unreachable. Jenkins sh steps
                    // do not inherit the systemd user session environment, so DOCKER_HOST
                    // is unset under rootless unless we set it here. Pattern borrowed
                    // from site-ffa-docker-test/Jenkinsfile.
                    if (sh(script: 'docker info >/dev/null 2>&1', returnStatus: true) != 0) {
                        def uid = sh(returnStdout: true, script: 'id -u').trim()
                        env.XDG_RUNTIME_DIR = "/run/user/${uid}"
                        env.DOCKER_HOST = "unix://${env.XDG_RUNTIME_DIR}/docker.sock"
                    }
                    sh 'docker info >/dev/null 2>&1 || { echo "ERROR: no usable Docker daemon (default and rootless socket tried)"; exit 1; }'

                    // In rootless mode the user namespace maps container uid 0 to the
                    // host user, so an explicit --user would resolve to an unmapped
                    // subordinate uid and break volume permissions. Detect rootlessness
                    // and drop --user for rootless; keep it for rootful daemons.
                    def isRootless = sh(script: 'docker info 2>/dev/null | grep -q rootless', returnStatus: true) == 0
                    echo "Docker rootless mode: ${isRootless}"
                    if (isRootless) {
                        env.DOCKER_USER_ARG = ''
                    } else {
                        def uid = sh(returnStdout: true, script: 'id -u').trim()
                        def gid = sh(returnStdout: true, script: 'id -g').trim()
                        env.DOCKER_USER_ARG = "--user ${uid}:${gid}"
                    }
                }
            }
        }

        stage('Build toolchain image') {
            steps {
                // --pull picks up base-image security updates; cheap insurance.
                sh '''#!/usr/bin/env bash
                    set -e
                    docker build --pull -t "$IMAGE_TAG" .
                '''
            }
        }

        stage('Build .deb') {
            steps {
                // Bind-mount the workspace into the container and run build.sh.
                // DOCKER_USER_ARG is '' under rootless (inner root = jenkins user)
                // or '--user <uid>:<gid>' under rootful (avoid root-owned artifacts).
                sh """#!/usr/bin/env bash
                    set -e
                    mkdir -p build
                    docker run --rm \\
                        ${env.DOCKER_USER_ARG} \\
                        --env HOME=/tmp \\
                        -v "\$PWD":/workspace \\
                        -w /workspace \\
                        "\$IMAGE_TAG" \\
                        ./build.sh
                """
            }
        }

        stage('Verify artifact') {
            steps {
                sh '''#!/usr/bin/env bash
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
