pipeline {
  agent any

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID = 'SONAR_TOKEN'        // Jenkins credential ID for Sonar token
    NVD_API_ID     = 'NVD_API_key'        // Jenkins credential ID for NVD API key (lowercase k)
    DC_DATA_DIR    = '/var/jenkins_home/dc-data'  // shared, persistent cache dir (not in workspace)
  }

  stages {
    stage('Checkout') {
      steps {
        git branch: 'main',
            credentialsId: 'github-pat',
            url: 'https://github.com/valletivarish/naveen_project.git'
      }
    }

    stage('Build with Maven') {
      steps {
        sh 'mvn -B -DskipTests -Dcheckstyle.skip=true clean package'
      }
    }

    stage('SonarQube Analysis') {
      steps {
        withCredentials([string(credentialsId: env.SONAR_TOKEN_ID, variable: 'SONAR_TOKEN')]) {
          sh """
            mvn -B sonar:sonar \
              -DskipTests \
              -Dcheckstyle.skip=true \
              -Dsonar.projectKey=petclinic \
              -Dsonar.projectName="petclinic" \
              -Dsonar.host.url=http://192.168.0.181:9000 \
              -Dsonar.token=${SONAR_TOKEN}
          """
        }
      }
    }

    stage('SCA - OWASP Dependency-Check (fast, no update, no reports)') {
      steps {
        retry(2) {
          withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
            withEnv(['MAVEN_OPTS=-Xms512m -Xmx3g -XX:+UseG1GC -Djava.awt.headless=true']) {
              sh """
                set -e
                mkdir -p "${DC_DATA_DIR}"

                # Run DC WITHOUT updating (avoids odc.update.lock waits and big downloads)
                mvn -B org.owasp:dependency-check-maven:check \
                   -DnvdApiKey=${NVD_API_KEY} \
                   -DdataDirectory="${DC_DATA_DIR}" \
                   -DautoUpdate=false \
                   -DnvdValidForHours=24 \
                   -DfailOnCVSS=11 \
                   -DskipTests

                # Do not keep any reports/artifacts
                find . -type f -name "dependency-check-report.*" -delete || true
                find . -path "*/target" -type f -name "dependency-check*" -delete || true
              """
            }
          }
        }
      }
    }
  }

  post {
    always {
      echo "Pipeline finished with status: ${currentBuild.currentResult}"
    }
  }
}
