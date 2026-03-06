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
  }

  stages {

    stage("Build image") {
      when { not { buildingTag() } }
      steps {
        script{
          withCredentials([usernamePassword(credentialsId: '28f3ae32-6a71-4b8e-8a3e-6191620a0492', usernameVariable: 'REDMINE_PLUGINS_USER', passwordVariable: 'REDMINE_PLUGINS_PASSWORD')]) {
            sh '''cp -f test/start_redmine.sh .'''
            sh '''A1_THEME_URL="https://cmshare.eea.europa.eu/remote.php/dav/files/${REDMINE_PLUGINS_USER}/redmine6-files/themes/a1_theme-4_1_2.zip" A1_THEME_USER="${REDMINE_PLUGINS_USER}" A1_THEME_PASSWORD="${REDMINE_PLUGINS_PASSWORD}" docker-compose -f test/docker-compose.yml up -d --build'''
            DOCKER_REDMINE = sh(script: "docker-compose -f test/docker-compose.yml ps | grep redmine | awk '{print \$1}'", returnStdout: true).trim()
            env.DOCKER_REDMINE = DOCKER_REDMINE
            // Fail fast if the image was built without A1 baked in.
            sh """docker exec ${DOCKER_REDMINE} bash -lc '
set -euo pipefail
THEMES_DIR=/usr/src/redmine/themes
if [ ! -d \"\$THEMES_DIR\" ]; then
  THEMES_DIR=/usr/src/redmine/public/themes
fi
test -d \"\$THEMES_DIR/a1\"
'"""
          }
        }
      }
    }

    stage("Prepare redmine for tests") {
      when { not { buildingTag() } }
      steps {
        sh '''docker exec ${DOCKER_REDMINE} /start_redmine.sh'''
      }
    }

    stage("Install A1 theme (Redmine 6 only)") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          // Ensure A1 exists and theme assets are usable via both digest and logical paths.
          sh '''
docker exec ${DOCKER_REDMINE} bash -lc '
set -euo pipefail

REDMINE_PATH=/usr/src/redmine
THEMES_DIR="${REDMINE_PATH}/themes"
A1_THEME_ID="${A1_THEME_ID:-a1}"
A1_ZIP="${A1_ZIP:-a1_theme-4_1_2.zip}"
TMP="/tmp/${A1_ZIP}"
THEME_CACHE="/install_themes/${A1_ZIP}"

is_valid_zip() {
  unzip -tqq "$1" >/dev/null 2>&1
}

if [ ! -d "$THEMES_DIR" ]; then
  echo "Skipping A1 theme install ($THEMES_DIR not present)"
  exit 0
fi

if [ ! -d "$THEMES_DIR/$A1_THEME_ID" ]; then
  if [ -f "$THEME_CACHE" ] && is_valid_zip "$THEME_CACHE"; then
    echo "Installing A1 theme from local cache: $THEME_CACHE"
    cp "$THEME_CACHE" "$TMP"
  else
    : "${PLUGINS_URL:?PLUGINS_URL is required when A1 cache is missing}"
    : "${PLUGINS_USER:?PLUGINS_USER is required when A1 cache is missing}"
    : "${PLUGINS_PASSWORD:?PLUGINS_PASSWORD is required when A1 cache is missing}"
    THEMES_URL="${A1_THEME_URL:-${PLUGINS_URL%/plugins}/themes}"
    echo "Installing A1 theme ($A1_ZIP) from $THEMES_URL into $THEMES_DIR"
    if command -v wget >/dev/null 2>&1; then
      wget -q --user="$PLUGINS_USER" --password="$PLUGINS_PASSWORD" -O "$TMP" "$THEMES_URL/$A1_ZIP"
    elif command -v curl >/dev/null 2>&1; then
      curl -fsSL -u "$PLUGINS_USER:$PLUGINS_PASSWORD" -o "$TMP" "$THEMES_URL/$A1_ZIP"
    else
      echo "Neither wget nor curl is available in the container"
      exit 1
    fi
    if ! is_valid_zip "$TMP"; then
      echo "Downloaded A1 archive is invalid: $THEMES_URL/$A1_ZIP"
      exit 1
    fi
  fi

  unzip -q -o "$TMP" -d "$THEMES_DIR"
  rm -f "$TMP"
fi

chown -R redmine:redmine "$THEMES_DIR/$A1_THEME_ID" || true

echo "Precompiling Redmine assets for A1 theme"
bundle exec rake assets:precompile RAILS_ENV=production

A1_ASSETS_DIR="${REDMINE_PATH}/public/assets/themes/${A1_THEME_ID}"
mkdir -p "$A1_ASSETS_DIR"
CSS_FILE="$(ls -1t "$A1_ASSETS_DIR"/application-*.css 2>/dev/null | head -n1 || true)"
JS_FILE="$(ls -1t "$A1_ASSETS_DIR"/theme-*.js 2>/dev/null | head -n1 || true)"

if [ -n "$CSS_FILE" ]; then
  ln -sfn "$(basename "$CSS_FILE")" "$A1_ASSETS_DIR/application.css"
fi
if [ -n "$JS_FILE" ]; then
  ln -sfn "$(basename "$JS_FILE")" "$A1_ASSETS_DIR/theme.js"
fi

ls -l "$A1_ASSETS_DIR"/application.css "$A1_ASSETS_DIR"/theme.js || true
'
'''
        }
      }
    }

    stage("Test plugins") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh "docker exec ${DOCKER_REDMINE} bundle exec rake redmine:plugins:test"
        }

        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh "docker cp ${DOCKER_REDMINE}:/usr/src/redmine/test/reports/TEST-Minitest-Result.xml TEST-Plugins-Result.xml"
          archiveArtifacts artifacts: "TEST-Plugins-Result.xml", fingerprint: true
        }
      }
    }
    stage("Unit tests (redmine)") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh "docker exec ${DOCKER_REDMINE} bundle exec rake test"
        }
        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh "docker cp ${DOCKER_REDMINE}:/usr/src/redmine/test/reports/TEST-Minitest-Result.xml TEST-Redmine-Result.xml"
          archiveArtifacts artifacts: "TEST-Redmine-Result.xml", fingerprint: true
        }
      }
    }
    stage("Integration/browser tests (redmine)") {
      when { not { buildingTag() } }
      steps {
        catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE') {
          sh "docker exec ${DOCKER_REDMINE} bundle exec rake test:system"
        }

        catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
          sh "docker cp ${DOCKER_REDMINE}:/usr/src/redmine/test/reports/TEST-Minitest-Result.xml TEST-Browser-Result.xml"
          archiveArtifacts artifacts: "TEST-Browser-Result.xml", fingerprint: true
        }
      }
      post {
        unstable {
          catchError(buildResult: 'SUCCESS', stageResult: 'SUCCESS') {
            sh "mkdir -p screenshots"
            sh "docker cp ${DOCKER_REDMINE}:/usr/src/redmine/tmp/screenshots/. screenshots/"
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
                   docker exec ${DOCKER_REDMINE} bash -lc 'cd /usr/src/redmine/test/reports && python3 /usr/src/redmine/test/merge_junitxml.py TEST-*-Result.xml TEST-Result.xml'
                   docker cp ${DOCKER_REDMINE}:/usr/src/redmine/test/reports/TEST-Result.xml TEST-Result.xml
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
            sh '''docker-compose -f test/docker-compose.yml stop'''
            sh '''docker-compose -f test/docker-compose.yml rm -vf'''
            sh '''docker rmi test_redmine'''
            sh '''docker volume rm test_taskman_test_db test_redmine_files'''
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
