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
            sh """
              set -x
              echo ">>> Running OWASP Dependency-Check via Maven plugin..."
              mkdir -p "${WORKSPACE}/${DC_REPORT_DIR}"

              mvn org.owasp:dependency-check-maven:check \
                -DnvdApiKey=${NVD_API_KEY} \
                -Dformat=HTML \
                -DoutputDirectory=${WORKSPACE}/${DC_REPORT_DIR} \
                -DskipTests

              echo ">>> Listing generated Dependency-Check reports:"
              ls -Rla "${WORKSPACE}/${DC_REPORT_DIR}" || true
            """

            def reportFile = "${WORKSPACE}/${DC_REPORT_DIR}/dependency-check-report.html"
            if (!fileExists(reportFile)) {
              error "❌ Dependency-Check HTML report not found at ${reportFile}. Check Maven logs for scan errors."
            } else {
              echo "✅ Dependency-Check HTML report generated successfully at ${reportFile}"
            }
          }
        }
      }

      post {
        always {
          echo ">>> Archiving and publishing Dependency-Check report..."
          sh 'ls -Rla "${WORKSPACE}/${DC_REPORT_DIR}" || true'

          archiveArtifacts artifacts: "${DC_REPORT_DIR}/**/*", fingerprint: true
          publishHTML target: [
            reportDir: "${DC_REPORT_DIR}",
            reportFiles: 'dependency-check-report.html',
            reportName: 'Dependency-Check Report',
            allowMissing: false,
            keepAll: true,
            alwaysLinkToLastBuild: true
          ]
        }
      }
    }

    // Future stages (e.g., Checkov, Trivy) can be added below
  }

  post {
    always {
      echo "Pipeline finished with status: ${currentBuild.currentResult}"
    }
  }
}
