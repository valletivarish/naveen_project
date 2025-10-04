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
        // Use the NVD API key from Jenkins credentials
        withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
          // ensure the report directory exists
          sh "mkdir -p ${DC_REPORT_DIR}"

          // Run Dependency-Check in Docker. This writes ALL formats into workspace/${DC_REPORT_DIR}
          // Note: `|| true` prevents failing the whole pipeline if dependency-check returns non-zero;
          // remove it if you want the pipeline to fail on findings.
          sh """
            docker run --rm \
              -v "${WORKSPACE}:/src" \
              -v "${WORKSPACE}/${DC_REPORT_DIR}:/report" \
              owasp/dependency-check:latest \
              --project "spring-petclinic" \
              --scan /src \
              --format ALL \
              --out /report \
              --nvdApiKey ${NVD_API_KEY} || true
          """
        }
      }
      post {
        always {
          // archive the report files (all formats)
          archiveArtifacts artifacts: "${DC_REPORT_DIR}/**/*", fingerprint: true

          // publish HTML (requires HTML Publisher plugin)
          publishHTML (target: [
            reportDir: "${DC_REPORT_DIR}",
            reportFiles: 'dependency-check-report.html',
            reportName: 'Dependency-Check Report',
            keepAll: true
          ])
        }
      }
    }

    // you will add Checkov & Trivy later as separate stages
  }

  post {
    always {
      echo "Pipeline finished with status: ${currentBuild.currentResult}"
    }
  }
}
