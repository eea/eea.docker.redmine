pipeline {
  agent any

  environment {
    GIT_NAME = "eea.docker.redmine"
    registry = "eeacms/redmine"
    template = "templates/taskman"
    DEPENDENT_DOCKERFILE_URL=""
  }
  
  stages {
  
    stage('Build & Test') {
      steps {
        node(label: 'docker') {
          script {
            try {
              checkout scm
              sh "mv test/start_redmine.sh ."
               
              withCredentials([ usernamePassword(credentialsId: 'redminepluginssvn', usernameVariable: 'REDMINE_PLUGINS_USER', passwordVariable: 'REDMINE_PLUGINS_PASSWORD')]) {
              
                  sh "docker-compose -f test/docker-compose.yml up -d"
                  DOCKER_REDMINE = sh (
                     script: "docker-compose -f test/docker-compose.yml ps | grep redmine | awk '{print \$1}'",
                     returnStdout: true
                  ).trim()
                  sh "docker exec ${DOCKER_REDMINE} /start_redmine.sh"
                  
                  sh "docker exec ${DOCKER_REDMINE} bundle exec rake redmine:plugins:test"
                  
                  sh "docker cp ${DOCKER_REDMINE}:/usr/src/redmine/test/reports/TEST-Minitest-Result.xml TEST-PLUGINS-Result.xml"
                                    
		  catchError(buildResult: 'SUCCESS', stageResult: 'UNSTABLE')  {
                      sh "docker exec ${DOCKER_REDMINE} bundle exec rake test"  
                  } 
                  
                  sh "docker cp ${DOCKER_REDMINE}:/usr/src/redmine/test/reports/TEST-Minitest-Result.xml TEST-Minitest-Result.xml"
                  
                  junit "TEST-PLUGINS-Result.xml"
                  junit "TEST-Minitest-Result.xml"
                  // archiveArtifacts artifacts: 'rake_test.log', fingerprint: true 
                  // archiveArtifacts artifacts: 'plugins_test.log', fingerprint: true
                          
                } 
            } finally {
              sh '''docker-compose -f test/docker-compose.yml stop'''
              sh '''docker-compose -f test/docker-compose.yml rm -vf'''
              sh '''docker rmi test_redmine'''
              sh '''docker volume ls'''
              sh '''docker volume rm test_taskman_test_db'''

            }
          }
        }
      }
    }





    stage('Release on tag creation') {
      when {
        buildingTag()
      }
      steps{
        node(label: 'docker') {
          withCredentials([string(credentialsId: 'eea-jenkins-token', variable: 'GITHUB_TOKEN'),  usernamePassword(credentialsId: 'jekinsdockerhub', usernameVariable: 'DOCKERHUB_USER', passwordVariable: 'DOCKERHUB_PASS')]) {
           sh '''docker pull eeacms/gitflow; docker run -i --rm --name="$BUILD_TAG"  -e GIT_BRANCH="$BRANCH_NAME" -e GIT_NAME="$GIT_NAME" -e DOCKERHUB_REPO="$registry" -e GIT_TOKEN="$GITHUB_TOKEN" -e DOCKERHUB_USER="$DOCKERHUB_USER" -e DOCKERHUB_PASS="$DOCKERHUB_PASS"  -e DEPENDENT_DOCKERFILE_URL="$DEPENDENT_DOCKERFILE_URL" -e RANCHER_CATALOG_PATHS="$template" -e GITFLOW_BEHAVIOR="RUN_ON_TAG" eeacms/gitflow'''
         }

        }
      }
    }


 }

  post {
    changed {
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
      }
    }
  }
}
