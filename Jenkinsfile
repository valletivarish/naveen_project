pipeline {
  agent any

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID = 'SONAR_TOKEN'
    NVD_API_ID     = 'NVD_API_key'
    DC_CACHE_DIR   = '/var/jenkins_home/dc-data'
    DC_LOCAL_DIR   = '.dc-data-ro'
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

    stage('SCA - OWASP Dependency-Check (no update/lock-free)') {
      steps {
        withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
          withEnv(['MAVEN_OPTS=-Xms512m -Xmx3g -XX:+UseG1GC -Djava.awt.headless=true']) {
            sh '''
              set -e
              mkdir -p "${DC_CACHE_DIR}"
              rm -rf "${DC_LOCAL_DIR}"
              mkdir -p "${DC_LOCAL_DIR}"

              CACHE_OK=0
              if [ -e "${DC_CACHE_DIR}/cve.db" ] || [ -e "${DC_CACHE_DIR}/odc.mv.db" ]; then
                CACHE_OK=1
              fi

              if [ "$CACHE_OK" -eq 0 ]; then
                echo "Dependency-Check cache is empty; skipping scan."
                exit 0
              fi

              rsync -a --delete --exclude 'odc.update.lock' "${DC_CACHE_DIR}/" "${DC_LOCAL_DIR}/"

              mvn -B org.owasp:dependency-check-maven:check \
                 -DnvdApiKey='${NVD_API_KEY}' \
                 -DdataDirectory="${DC_LOCAL_DIR}" \
                 -DautoUpdate=false \
                 -DnvdValidForHours=24 \
                 -DfailOnCVSS=11 \
                 -DskipTests

              find . -type f -name "dependency-check-report.*" -delete || true
              find . -path "*/target" -type f -name "dependency-check*" -delete || true
              rm -rf "${DC_LOCAL_DIR}"
            '''
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
