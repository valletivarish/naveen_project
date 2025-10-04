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
    DC_UPDATE_DIR  = '.dc-data-update'
    DC_FRESH_HOURS = '24'
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
          withEnv(['MAVEN_OPTS=-Xms512m -Xmx3g -XX:+UseG1GC -Djava.awt.headless=true']) {
            sh '''
              set -e
              mkdir -p "${DC_CACHE_DIR}"
              rm -rf "${DC_LOCAL_DIR}" "${DC_UPDATE_DIR}"
              mkdir -p "${DC_LOCAL_DIR}" "${DC_UPDATE_DIR}"

              FRESH_SECS=$(( ${DC_FRESH_HOURS:-24} * 3600 ))
              DB_PATH=""
              if [ -e "${DC_CACHE_DIR}/odc.mv.db" ]; then DB_PATH="${DC_CACHE_DIR}/odc.mv.db"; elif [ -e "${DC_CACHE_DIR}/cve.db" ]; then DB_PATH="${DC_CACHE_DIR}/cve.db"; fi

              IS_FRESH=0
              if [ -n "$DB_PATH" ]; then
                AGE=$(( $(date +%s) - $(stat -c %Y "$DB_PATH") ))
                [ $AGE -lt $FRESH_SECS ] && IS_FRESH=1
              fi

              if [ $IS_FRESH -eq 0 ]; then
                set +e
                timeout 25m sh -c '
                  mvn -B org.owasp:dependency-check-maven:update-only \
                     -DnvdApiKey='"${NVD_API_KEY}"' \
                     -DdataDirectory="'"${DC_UPDATE_DIR}"'"
                '
                RC=$?
                set -e
                if [ $RC -eq 0 ] && { [ -e "${DC_UPDATE_DIR}/odc.mv.db" ] || [ -e "${DC_UPDATE_DIR}/cve.db" ]; }; then
                  rm -rf "${DC_CACHE_DIR:?}/"* || true
                  cp -R "${DC_UPDATE_DIR}/." "${DC_CACHE_DIR}/"
                fi
              fi

              if [ ! -e "${DC_CACHE_DIR}/odc.mv.db" ] && [ ! -e "${DC_CACHE_DIR}/cve.db" ]; then
                echo "No NVD database available; skipping Dependency-Check."
                exit 0
              fi

              rm -rf "${DC_LOCAL_DIR:?}/"* || true
              cp -R "${DC_CACHE_DIR}/." "${DC_LOCAL_DIR}/" || true
              rm -f "${DC_LOCAL_DIR}/odc.update.lock" || true

              mvn -B org.owasp:dependency-check-maven:check \
                 -DnvdApiKey='${NVD_API_KEY}' \
                 -DdataDirectory="${DC_LOCAL_DIR}" \
                 -DautoUpdate=false \
                 -DnvdValidForHours=${DC_FRESH_HOURS} \
                 -DfailOnCVSS=11 \
                 -DskipTests
            '''
          }
        }
      }

      post {
        always {
          archiveArtifacts artifacts: 'target/dependency-check-report.html', fingerprint: true
          publishHTML target: [
            reportDir: 'target',
            reportFiles: 'dependency-check-report.html',
            reportName: 'OWASP Dependency-Check Report',
            keepAll: true,
            alwaysLinkToLastBuild: true
          ]
        }
      }
    }

    stage('Container Build & Scan (Trivy)') {
      steps {
        script {
          def imgTag = "petclinic-app:${env.BUILD_NUMBER}"

          sh """
            echo '>>> Building Docker image: ${imgTag}'
            docker build -t ${imgTag} .
            docker images ${imgTag} || true
          """

          sh """
            echo '>>> Running Trivy (this may fetch vuln DB on first run)'
            docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
              aquasec/trivy:latest image --scanners vuln --format json --output trivy-report.json ${imgTag} || true
          """

          sh '''
            if [ -f trivy-report.json ]; then
              jq '{Results: .}' trivy-report.json > trivy-summary.json || true
              echo "<html><body><h3>Trivy report (summary)</h3><pre>" > trivy-summary.html || true
              jq . trivy-report.json >> trivy-summary.html || true
              echo "</pre></body></html>" >> trivy-summary.html || true
            fi
          '''
        }
      }

      post {
        always {
          archiveArtifacts artifacts: 'trivy-report.json, trivy-summary.html', fingerprint: true
          publishHTML target: [
            reportDir: '.',
            reportFiles: 'trivy-summary.html',
            reportName: 'Trivy Summary',
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
