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
          script {
            def hostIp = sh(script: "ip route get 1 2>/dev/null | awk '{print \$7; exit}' || hostname -I 2>/dev/null | awk '{print \$1}' || echo 127.0.0.1", returnStdout: true).trim()
            sh """
              mvn -B sonar:sonar \
                -DskipTests \
                -Dcheckstyle.skip=true \
                -Dsonar.projectKey=petclinic \
                -Dsonar.projectName="petclinic" \
                -Dsonar.host.url=http://${hostIp}:9000 \
                -Dsonar.token=${SONAR_TOKEN}
            """
          }
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
          archiveArtifacts artifacts: 'target/dependency-check-report.html', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [
            reportDir: 'target',
            reportFiles: 'dependency-check-report.html',
            reportName: 'OWASP Dependency-Check Report',
            keepAll: true,
            alwaysLinkToLastBuild: true,
            allowMissing: true
          ]
        }
      }
    }

    stage('Container Build & Scan (Trivy)') {
      steps {
        script {
          def imgTag = "petclinic-app:${env.BUILD_NUMBER}"
          sh '''
            set -e
            if command -v docker >/dev/null 2>&1; then
              echo ">>> Docker detected. Building image and scanning with Trivy image scanner."
              docker build -t '"${imgTag}"' .
              docker images '"${imgTag}"' || true

              docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                -v "$PWD:/work" -w /work \
                aquasec/trivy:latest image --scanners vuln \
                --format json --output trivy-report.json '"${imgTag}"' || true

              docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
                -v "$PWD:/work" -w /work \
                aquasec/trivy:latest image --scanners vuln \
                --format table --output trivy-summary.txt '"${imgTag}"' || true
            else
              echo ">>> Docker not found. Downloading Trivy CLI and running filesystem scan."
              TRIVY_VER="0.55.0"
              rm -f trivy trivy.tgz || true
              curl -sSL -o trivy.tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-64bit.tar.gz"
              tar -xzf trivy.tgz trivy
              chmod +x trivy

              ./trivy fs --scanners vuln --format json --output trivy-report.json . || true
              ./trivy fs --scanners vuln --format table --output trivy-summary.txt . || true
            fi

            if [ -f trivy-summary.txt ]; then
              {
                echo "<html><body><h3>Trivy Summary</h3><pre>";
                sed -e 's/&/\\&amp;/g' -e 's/</\\&lt;/g' trivy-summary.txt;
                echo "</pre></body></html>";
              } > trivy-summary.html || true
            fi
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'trivy-report.json, trivy-summary.html, trivy-summary.txt', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [
            reportDir: '.',
            reportFiles: 'trivy-summary.html',
            reportName: 'Trivy Summary',
            keepAll: true,
            alwaysLinkToLastBuild: true,
            allowMissing: true
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
