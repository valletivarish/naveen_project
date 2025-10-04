pipeline {
  agent any

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID = 'SONAR_TOKEN'   // Jenkins credential ID for Sonar token
    NVD_API_ID     = 'NVD_API_key'   // Jenkins credential ID for NVD API key
    DC_DATA_DIR    = '.dc-data'      // Cache dir for Dependency-Check NVD database
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

    stage('SCA - OWASP Dependency-Check (no report persistence)') {
      steps {
        retry(2) {
          withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
            // Give the DC step a larger heap and cache its DB between runs
            withEnv(['MAVEN_OPTS=-Xms512m -Xmx3g -XX:+UseG1GC -Djava.awt.headless=true']) {
              sh """
                set -x
                echo ">>> Using cached NVD data directory: \${WORKSPACE}/${DC_DATA_DIR}"
                mkdir -p "\${WORKSPACE}/${DC_DATA_DIR}"

                echo ">>> Running OWASP Dependency-Check via Maven (reports not persisted)..."
                mvn -B org.owasp:dependency-check-maven:check \
                   -DnvdApiKey=${NVD_API_KEY} \
                   -DdataDirectory="\${WORKSPACE}/${DC_DATA_DIR}" \
                   -DfailOnCVSS=11 \
                   -DskipTests

                echo ">>> Cleaning any generated Dependency-Check report artifacts..."
                find . -type f -name "dependency-check-report.*" -delete || true
                find . -type f -name "dependency-check-suppression.*" -delete || true
                find . -path "*/target" -type f -name "dependency-check*" -delete || true

                echo ">>> OWASP Dependency-Check completed. No reports saved or published."
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
