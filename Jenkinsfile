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
          withCredentials([usernamePassword(credentialsId: 'redminepluginssvn', usernameVariable: 'REDMINE_PLUGINS_USER', passwordVariable: 'REDMINE_PLUGINS_PASSWORD')]) {
            sh '''mv test/start_redmine.sh .'''
            sh '''docker-compose -f test/docker-compose.yml up -d --build'''
            DOCKER_REDMINE = sh(script: "docker-compose -f test/docker-compose.yml ps | grep redmine | awk '{print \$1}'", returnStdout: true).trim()
            env.DOCKER_REDMINE = DOCKER_REDMINE
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
            sh '''python merge_junitxml.py TEST-*-Result.xml TEST-Result.xml'''
            junit "TEST-Result.xml"
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
