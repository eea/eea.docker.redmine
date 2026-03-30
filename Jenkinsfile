pipeline {
  agent {
    node {
      label "docker-host"
    }
  }

  environment {
    GIT_NAME = "eea.docker.redmine"
    registry = "eeacms/redmine"
    template = "templates/taskman"
    DEPENDENT_DOCKERFILE_URL = ""
    ENFORCE_PUBLISHED_IMAGE_POLICY = "0"
  }

  stages {

    stage("Build image") {
      when { not { buildingTag() } }
      steps {
        script{
          withCredentials([usernamePassword(credentialsId: '28f3ae32-6a71-4b8e-8a3e-6191620a0492', usernameVariable: 'CI_PLUGINS_USER', passwordVariable: 'CI_PLUGINS_PASSWORD')]) {
          sh '''
set -euo pipefail

PLUGIN_SHARE_USER="${REDMINE_PLUGINS_USER:-${PLUGINS_USER:-${CI_PLUGINS_USER:-}}}"
PLUGIN_SHARE_PASSWORD="${REDMINE_PLUGINS_PASSWORD:-${PLUGINS_PASSWORD:-${CI_PLUGINS_PASSWORD:-}}}"

if [ -z "${PLUGIN_SHARE_USER}" ] || [ -z "${PLUGIN_SHARE_PASSWORD}" ]; then
  if [ -f .env ]; then
    set -a
    # shellcheck disable=SC1091
    . ./.env
    set +a
    PLUGIN_SHARE_USER="${PLUGIN_SHARE_USER:-${REDMINE_PLUGINS_USER:-${PLUGINS_USER:-}}}"
    PLUGIN_SHARE_PASSWORD="${PLUGIN_SHARE_PASSWORD:-${REDMINE_PLUGINS_PASSWORD:-${PLUGINS_PASSWORD:-}}}"
  fi
fi

: "${PLUGIN_SHARE_USER:?Share-based addons sync requires REDMINE_PLUGINS_USER or PLUGINS_USER}"
: "${PLUGIN_SHARE_PASSWORD:?Share-based addons sync requires REDMINE_PLUGINS_PASSWORD or PLUGINS_PASSWORD}"

ADDONS_SYNC_SOURCE=share \
ADDONS_SYNC_SKIP_IF_PRESENT=0 \
REDMINE_PLUGINS_USER="${PLUGIN_SHARE_USER}" \
REDMINE_PLUGINS_PASSWORD="${PLUGIN_SHARE_PASSWORD}" \
PLUGINS_USER="${PLUGIN_SHARE_USER}" \
PLUGINS_PASSWORD="${PLUGIN_SHARE_PASSWORD}" \
REDMINE_BUILD_TARGET=ci-runtime \
docker-compose -f test/docker-compose.yml down -v --remove-orphans || true

ADDONS_SYNC_SOURCE=share \
ADDONS_SYNC_SKIP_IF_PRESENT=0 \
REDMINE_PLUGINS_USER="${PLUGIN_SHARE_USER}" \
REDMINE_PLUGINS_PASSWORD="${PLUGIN_SHARE_PASSWORD}" \
PLUGINS_USER="${PLUGIN_SHARE_USER}" \
PLUGINS_PASSWORD="${PLUGIN_SHARE_PASSWORD}" \
REDMINE_BUILD_TARGET=ci-runtime \
docker-compose -f test/docker-compose.yml up -d --build || {
  echo "Initial docker-compose up failed; collecting diagnostics and retrying once..." >&2
  docker-compose -f test/docker-compose.yml ps -a || true
  docker-compose -f test/docker-compose.yml logs --no-color addons-sync migrate mysql redmine || true
  # Reset compose state/volumes so retry starts from a clean DB and avoids partially-applied migrations.
  docker-compose -f test/docker-compose.yml down -v --remove-orphans || true
  docker-compose -f test/docker-compose.yml up -d --build
}
'''
          }
          sh '''
set -euo pipefail
for _ in $(seq 1 120); do
  cid="$(docker-compose -f test/docker-compose.yml ps -q redmine || true)"
  if [ -n "${cid}" ] && docker inspect "${cid}" >/dev/null 2>&1; then
    running="$(docker inspect -f '{{.State.Running}}' "${cid}" 2>/dev/null || true)"
    if [ "${running}" = "true" ]; then
      exit 0
    fi
  fi
  sleep 2
done
echo "Timed out waiting for redmine service container to be running" >&2
docker-compose -f test/docker-compose.yml ps || true
docker-compose -f test/docker-compose.yml logs --no-color migrate || true
exit 1
'''
          def DOCKER_REDMINE = sh(script: "docker-compose -f test/docker-compose.yml ps -q redmine", returnStdout: true).trim()
          if (!DOCKER_REDMINE) {
            error("Unable to resolve redmine container id from docker-compose")
          }
          env.DOCKER_REDMINE = DOCKER_REDMINE
          // Enforce policy only for publish flows when explicitly enabled.
          if (env.ENFORCE_PUBLISHED_IMAGE_POLICY != "1") {
            echo "Skipping published-image policy check in regular Jenkins CI (ENFORCE_PUBLISHED_IMAGE_POLICY=${env.ENFORCE_PUBLISHED_IMAGE_POLICY})"
          } else {
            sh '''
cat <<'SCRIPT' | docker run --rm --entrypoint bash test-redmine:latest -s
set -euo pipefail
for plugin in redmine_agile redmine_checklists redmine_contacts_helpdesk redmine_contacts redmine_reporter redmine_zenedit redmine_resources; do
  if [ -d "/usr/src/redmine/plugins/${plugin}" ]; then
    echo "Paid plugin is embedded in image but should be mounted at runtime: ${plugin}" >&2
    exit 1
  fi
done
if [ -d /usr/src/redmine/themes/a1 ] || [ -d /usr/src/redmine/public/themes/a1 ]; then
  echo "A1 theme is embedded in image but should be mounted at runtime" >&2
  exit 1
fi
SCRIPT
'''
          }
        }
      }
    }

    stage("Prepare redmine for tests") {
      when { not { buildingTag() } }
      steps {
        sh '''docker-compose -f test/docker-compose.yml exec -T redmine bash -lc "START_SERVER=0 START_CRON=0 START_SOLID_QUEUE=0 RUN_DB_MIGRATE=1 RUN_PLUGIN_MIGRATE=auto ASSETS_PRECOMPILE=1 ASSETS_PRECOMPILE_FORCE=1 RAILS_ENV=test /start_redmine.sh"'''
      }
    }

    stage("Install A1 theme (Redmine 6 only)") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          // In this pipeline, A1 is provided as mounted addon data, not baked into image.
          sh '''
docker-compose -f test/docker-compose.yml exec -T redmine bash -lc '
set -euo pipefail

THEMES_DIR=/usr/src/redmine/themes
if [ ! -d "$THEMES_DIR" ]; then
  THEMES_DIR=/usr/src/redmine/public/themes
fi
if [ ! -d "$THEMES_DIR/a1" ]; then
  echo "A1 theme is not available in mounted addons runtime path: $THEMES_DIR/a1" >&2
  exit 1
fi
ls -la "$THEMES_DIR/a1" | head -n 20
'
'''
        }
      }
    }

    stage("Test plugins") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh '''
set -euo pipefail
docker-compose -f test/docker-compose.yml exec -T redmine bash -lc '
set -euo pipefail
mkdir -p /usr/src/redmine/test/reports
bundle exec rake redmine:plugins:test --verbose 2>&1 | tee /usr/src/redmine/test/reports/plugins-test-output.log
'
'''
        }

        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh '''
set -euo pipefail
cid="$(docker-compose -f test/docker-compose.yml ps -q redmine)"
found=0
for report in TEST-Minitest-Result.xml TEST-Result.xml; do
  src="/usr/src/redmine/test/reports/${report}"
  if docker exec "${cid}" test -f "${src}"; then
    docker cp "${cid}:${src}" TEST-Plugins-Result.xml
    found=1
    break
  fi
done
if [ "${found}" != "1" ]; then
  echo "No plugin junit report found under /usr/src/redmine/test/reports" >&2
  docker exec "${cid}" ls -la /usr/src/redmine/test/reports || true
fi
docker exec "${cid}" test -f /usr/src/redmine/test/reports/plugins-test-output.log && \
  docker cp "${cid}:/usr/src/redmine/test/reports/plugins-test-output.log" TEST-Plugins-Output.log || true
exit 0
'''
          archiveArtifacts artifacts: "TEST-Plugins-Result.xml", fingerprint: true, allowEmptyArchive: true
          archiveArtifacts artifacts: "TEST-Plugins-Output.log", fingerprint: true, allowEmptyArchive: true
        }
      }
    }
    stage("Unit tests (redmine)") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh "docker-compose -f test/docker-compose.yml exec -T redmine bundle exec rake test"
        }
        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh '''
set -euo pipefail
cid="$(docker-compose -f test/docker-compose.yml ps -q redmine)"
found=0
for report in TEST-Minitest-Result.xml TEST-Result.xml; do
  src="/usr/src/redmine/test/reports/${report}"
  if docker exec "${cid}" test -f "${src}"; then
    docker cp "${cid}:${src}" TEST-Redmine-Result.xml
    found=1
    break
  fi
done
if [ "${found}" != "1" ]; then
  echo "No unit-test junit report found under /usr/src/redmine/test/reports" >&2
  docker exec "${cid}" ls -la /usr/src/redmine/test/reports || true
  exit 0
fi
'''
          archiveArtifacts artifacts: "TEST-Redmine-Result.xml", fingerprint: true, allowEmptyArchive: true
        }
      }
    }
    stage("Integration/browser tests (redmine)") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh "docker-compose -f test/docker-compose.yml exec -T redmine bundle exec rake test:system"
        }

        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh '''
set -euo pipefail
cid="$(docker-compose -f test/docker-compose.yml ps -q redmine)"
found=0
for report in TEST-Minitest-Result.xml TEST-Result.xml; do
  src="/usr/src/redmine/test/reports/${report}"
  if docker exec "${cid}" test -f "${src}"; then
    docker cp "${cid}:${src}" TEST-Browser-Result.xml
    found=1
    break
  fi
done
if [ "${found}" != "1" ]; then
  echo "No browser-test junit report found under /usr/src/redmine/test/reports" >&2
  docker exec "${cid}" ls -la /usr/src/redmine/test/reports || true
  exit 0
fi
'''
          archiveArtifacts artifacts: "TEST-Browser-Result.xml", fingerprint: true, allowEmptyArchive: true
        }
      }
      post {
        unstable {
          catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
            sh "mkdir -p screenshots"
            sh 'docker cp $(docker-compose -f test/docker-compose.yml ps -q redmine):/usr/src/redmine/tmp/screenshots/. screenshots/'
            archiveArtifacts artifacts: "screenshots/*", fingerprint: true
          }
        }
      }
    }

    stage('Release on tag creation') {
      when {
        buildingTag()
      }
      steps {
        node(label: 'docker') {
          withCredentials([string(credentialsId: 'eea-jenkins-token', variable: 'GITHUB_TOKEN'), usernamePassword(credentialsId: 'jekinsdockerhub', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
            sh '''docker pull eeacms/gitflow; docker run -i --rm --name="$BUILD_TAG"  -e GIT_BRANCH="$BRANCH_NAME" -e GIT_NAME="$GIT_NAME" -e DOCKERHUB_REPO="$registry" -e GIT_TOKEN="$GITHUB_TOKEN" -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS"  -e DEPENDENT_DOCKERFILE_URL="$DEPENDENT_DOCKERFILE_URL" -e RANCHER_CATALOG_PATHS="$template" -e GITFLOW_BEHAVIOR="RUN_ON_TAG" eeacms/gitflow'''
          }

        }
      }
    }

  }

  post {
    always {
      script {
        if (env.DOCKER_REDMINE) {
           catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
             sh '''cp test/merge_junitxml.py .'''
             // Some Jenkins agents don't have `python` in PATH. Prefer python3, then python.
             // If neither is available on the agent, run the merge inside the redmine container
             // which has python3.
             sh '''
               if ls TEST-*-Result.xml >/dev/null 2>&1; then
                 if command -v python3 >/dev/null 2>&1; then
                   python3 merge_junitxml.py TEST-*-Result.xml TEST-Result.xml
                 elif command -v python >/dev/null 2>&1; then
                   python merge_junitxml.py TEST-*-Result.xml TEST-Result.xml
                 else
                   docker-compose -f test/docker-compose.yml exec -T redmine bash -lc 'cd /usr/src/redmine/test/reports && python3 /usr/src/redmine/test/merge_junitxml.py TEST-*-Result.xml TEST-Result.xml'
                   docker cp $(docker-compose -f test/docker-compose.yml ps -q redmine):/usr/src/redmine/test/reports/TEST-Result.xml TEST-Result.xml
                 fi
               else
                 echo "No junit xml artifacts found; skipping merge step"
               fi
             '''
             if (fileExists('TEST-Result.xml')) {
               junit "TEST-Result.xml"
             } else {
               echo "Skipping junit publish: TEST-Result.xml missing"
             }
           }

          catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
            sh '''REDMINE_BUILD_TARGET=ci-runtime docker-compose -f test/docker-compose.yml stop'''
            sh '''REDMINE_BUILD_TARGET=ci-runtime docker-compose -f test/docker-compose.yml rm -vf'''
            sh '''docker rmi test_redmine || true'''
            sh '''docker volume rm test_taskman_test_db_mysql84 test_redmine_files'''
          }
        }
      }
        cleanWs(cleanWhenAborted: true, cleanWhenFailure: true, cleanWhenNotBuilt: true, cleanWhenSuccess: true, cleanWhenUnstable: true, deleteDirs: true)

        script {

          def url = "${env.BUILD_URL}/display/redirect"
          def status = currentBuild.currentResult
          def subject = "${status}: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'"
          def summary = "${subject} (${url})"
          def details = """<h1>${env.JOB_NAME} - Build #${env.BUILD_NUMBER} - ${status}</h1>
                           <p>Check console output at <a href="${url}">${env.JOB_BASE_NAME} - #${env.BUILD_NUMBER}</a></p>
                        """

          def color = '#FFFF00'
          if (status == 'SUCCESS') {
            color = '#00FF00'
          } else if (status == 'FAILURE') {
            color = '#FF0000'
          }

          def recipients = emailextrecipients([[$class: 'DevelopersRecipientProvider'], [$class: 'CulpritsRecipientProvider']])

          echo "Recipients is ${recipients}"

          emailext(
          subject: '$DEFAULT_SUBJECT', body: details, attachLog: false, compressLog: true, recipientProviders: [[$class: 'DevelopersRecipientProvider'], [$class: 'CulpritsRecipientProvider']])

        }
      }
    }
  }
