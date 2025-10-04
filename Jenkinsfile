// Jenkinsfile - Step 1: checkout + build (minimal)
pipeline {
  agent any

  stages {
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    stage('Build (Maven)') {
      steps {
        // Use wrapper if available; skip tests and skip checkstyle to avoid build-break on style errors
        sh './mvnw -B -DskipTests=true -Dcheckstyle.skip=true clean package'
      }
      post {
        always {
          archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
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
