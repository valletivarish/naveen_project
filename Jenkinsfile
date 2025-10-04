pipeline {
  agent any

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID = 'SONAR_TOKEN'
    NVD_API_ID    = 'NVD_API_KEY'   // Jenkins credential ID for NVD API key
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
        withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
          sh """
            set -x
            echo ">>> Running OWASP Dependency-Check via Maven plugin (no report saved/published)..."

            # Run scan; never fail build on CVSS by setting threshold above 10
            mvn -B org.owasp:dependency-check-maven:check \
               -DnvdApiKey=${NVD_API_KEY} \
               -DfailOnCVSS=11 \
               -DskipTests

            echo ">>> Cleaning up any Dependency-Check artifacts so nothing persists..."
            # Common DC outputs live under target/; remove them
            find . -type f -name "dependency-check-report.*" -delete || true
            find . -type f -name "dependency-check-suppression.*" -delete || true
            find . -type d -name "dependency-check-data" -prune -exec rm -rf {} + || true
            # Some versions leave files in module targets:
            find . -path "*/target" -type f -name "dependency-check*" -delete || true

            echo ">>> OWASP scan completed. No reports were saved or published."
          """
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
