pipeline {
  agent any

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID = 'SONAR_TOKEN'
    NVD_API_ID    = 'NVD_API_KEY'
    DC_REPORT_DIR = 'dependency-check-report'
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
        withCredentials([
          string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY'),
          usernamePassword(credentialsId: 'github-pat', usernameVariable: 'GIT_USER', passwordVariable: 'GIT_TOKEN')
        ]) {
          script {
            sh """
              set -x
              mkdir -p "${WORKSPACE}/${DC_REPORT_DIR}"
              echo ">>> Running OWASP Dependency-Check..."
              mvn org.owasp:dependency-check-maven:check \
                -DnvdApiKey=${NVD_API_KEY} \
                -Dformat=HTML \
                -DoutputDirectory=${WORKSPACE}/${DC_REPORT_DIR} \
                -DskipTests

              echo ">>> Listing generated reports:"
              ls -Rla "${WORKSPACE}/${DC_REPORT_DIR}" || true
            """

            def reportFile = "${WORKSPACE}/${DC_REPORT_DIR}/dependency-check-report.html"
            if (!fileExists(reportFile)) {
              error "❌ Dependency-Check HTML report not found at ${reportFile}. Check Maven logs."
            } else {
              echo "✅ Dependency-Check HTML report generated successfully."
            }

            // Push reports to GitHub branch
            sh """
              echo ">>> Pushing Dependency-Check report to GitHub branch 'dependency-check-reports'..."
              cd "${WORKSPACE}"
              git config user.email "jenkins@local"
              git config user.name "Jenkins CI"

              git fetch origin
              git checkout -B dependency-check-reports
              rm -rf dependency-check-report || true
              mkdir dependency-check-report
              cp -r ${DC_REPORT_DIR}/* dependency-check-report/ || true

              git add dependency-check-report
              git commit -m "Add latest OWASP Dependency-Check report [ci skip]" || echo "No changes to commit"
              git push https://${GIT_USER}:${GIT_TOKEN}@github.com/valletivarish/naveen_project.git dependency-check-reports --force
            """
          }
        }
      }

      post {
        always {
          archiveArtifacts artifacts: "${DC_REPORT_DIR}/**/*", fingerprint: true
          publishHTML target: [
            reportDir: "${DC_REPORT_DIR}",
            reportFiles: 'dependency-check-report.html',
            reportName: 'Dependency-Check Report',
            allowMissing: true,
            keepAll: true,
            alwaysLinkToLastBuild: true
          ]
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
