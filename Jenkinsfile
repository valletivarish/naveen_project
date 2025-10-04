pipeline {
  agent any

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID = 'SONAR_TOKEN'
    NVD_API_ID    = 'NVD_API_KEY'   // Jenkins credential ID for NVD API key
    DC_REPORT_DIR = 'dependency-check-report' // path inside workspace to store reports
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

    stage('SCA - OWASP Dependency-Check') {
      steps {
        withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
          script {
            // prepare workspace & debug before running
            sh """
              set -x
              echo ">>> WORKSPACE: ${WORKSPACE}"
              mkdir -p "${WORKSPACE}/${DC_REPORT_DIR}"
              ls -la "${WORKSPACE}" || true
              ls -la "${WORKSPACE}/${DC_REPORT_DIR}" || true
              echo ">>> Starting OWASP dependency-check (this may download NVD DB and take time)"
            """

            // run dependency-check docker container (no '|| true' so failures surface)
            sh """
              docker run --rm \
                -v "${WORKSPACE}:/src" \
                -v "${WORKSPACE}/${DC_REPORT_DIR}:/report" \
                owasp/dependency-check:latest \
                --project "spring-petclinic" \
                --scan /src \
                --format ALL \
                --out /report \
                --nvdApiKey ${NVD_API_KEY}
            """

            // list results
            sh """
              echo '>>> After docker run: listing report dir:'
              ls -la "${WORKSPACE}/${DC_REPORT_DIR}" || true
              echo '>>> HTML files (if any):'
              ls -la "${WORKSPACE}/${DC_REPORT_DIR}"/*.html || true
            """

            // validate reports exist; fail with a clear message if missing
            def out = sh(script: "test -d \"${WORKSPACE}/${DC_REPORT_DIR}\" -a -n \"\$(ls -A ${WORKSPACE}/${DC_REPORT_DIR} 2>/dev/null)\" && echo OK || echo MISSING", returnStdout: true).trim()
            if (out != 'OK') {
              error "Dependency-Check did not produce any reports in ${WORKSPACE}/${DC_REPORT_DIR} — check console output above for docker errors or NVD DB download issues."
            }
          } // script
        } // withCredentials
      } // steps

      post {
        always {
          archiveArtifacts artifacts: "${DC_REPORT_DIR}/**/*", fingerprint: true
          publishHTML target: [
            reportDir: "${DC_REPORT_DIR}",
            reportFiles: 'dependency-check-report.html',
            reportName: 'Dependency-Check Report',
            keepAll: true
          ]
        }
      }
    }

    // later we will add Checkov & Trivy stages
  }

  post {
    always {
      echo "Pipeline finished with status: ${currentBuild.currentResult}"
    }
  }
}
