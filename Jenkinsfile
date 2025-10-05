pipeline {
  agent any

  parameters {
    string(name: 'GIT_BRANCH', defaultValue: 'main', description: 'Git branch to build (e.g. main or test/scanner-check)')
  }

  tools {
    maven 'Maven3'
    jdk 'JDK17'
  }

  environment {
    SONAR_TOKEN_ID   = 'SONAR_TOKEN'
    NVD_API_ID       = 'NVD_API_key'
    DC_CACHE_DIR     = '/var/jenkins_home/dc-data'
    DC_LOCAL_DIR     = '.dc-data-ro'
    DC_UPDATE_DIR    = '.dc-data-update'
    DC_FRESH_HOURS   = '24'
    TRIVY_VER        = '0.55.0'
    TRIVY_CACHE_DIR  = '/var/jenkins_home/trivy-cache'
    TRIVY_FRESH_HOURS= '12'
    TRIVY_SEVERITY   = 'LOW,MEDIUM,HIGH,CRITICAL'
    TRIVY_STRICT_SEV = 'HIGH,CRITICAL'
    TRIVY_IGNORE_UNFIXED = 'false'
    IMAGE_NAME       = 'petclinic-app'
  }

  stages {
    stage('Preflight: Docker & Permissions') {
      steps {
        sh '''
          set -e
          echo ">>> Checking Docker availability"
          if ! command -v docker >/dev/null 2>&1; then echo "ERROR: docker CLI not installed"; exit 1; fi
          docker version || { echo "ERROR: Cannot talk to Docker daemon"; exit 1; }
          docker run --rm hello-world >/dev/null 2>&1 || { echo "ERROR: Cannot run containers (check socket permissions)"; exit 1; }
          echo ">>> Docker is ready"
        '''
      }
    }

    stage('Checkout') {
      steps {
        script {
          def branch = params.GIT_BRANCH ?: 'main'
          echo "Checking out branch: ${branch}"
          git branch: branch, credentialsId: 'github-pat', url: 'https://github.com/valletivarish/naveen_project.git'
        }
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
          sh '''
            set -e
            probe(){ url="$1"; [ -z "$url" ] && return 1; curl -sSf --max-time 3 "$url/api/system/status" >/dev/null 2>&1; }
            GATEWAY_IP="$(ip route | awk '/default/ {print $3; exit}')" || true
            FIRST_IPV4="$(ip -4 addr show scope global 2>/dev/null | awk "/inet /{print \\$2}" | cut -d/ -f1 | head -n1)" || true
            HOST_IP_ALT="$(hostname -I 2>/dev/null | awk "{print \\$1}")" || true
            CANDS="${SONAR_HOST_URL:-} http://localhost:9000 http://127.0.0.1:9000 http://${GATEWAY_IP}:9000 http://host.docker.internal:9000 http://${FIRST_IPV4}:9000 http://${HOST_IP_ALT}:9000"
            for u in $CANDS; do if probe "$u"; then SURL="$u"; break; fi; done
            if [ -z "$SURL" ]; then echo "WARN: no reachable SonarQube; skipping analysis."; exit 0; fi
            mvn -B org.sonarsource.scanner.maven:sonar-maven-plugin:4.0.0.4121:sonar \
              -DskipTests -Dcheckstyle.skip=true \
              -Dsonar.projectKey=petclinic -Dsonar.projectName="petclinic" \
              -Dsonar.host.url="$SURL" -Dsonar.token="$SONAR_TOKEN"
          '''
        }
      }
    }

    stage('SCA - OWASP Dependency-Check') {
      steps {
        withCredentials([string(credentialsId: env.NVD_API_ID, variable: 'NVD_API_KEY')]) {
          withEnv(['MAVEN_OPTS=-Xms512m -Xmx3g -XX:+UseG1GC -Djava.awt.headless=true']) {
            sh '''
              set -e
              mkdir -p "${DC_CACHE_DIR}" "${DC_LOCAL_DIR}" "${DC_UPDATE_DIR}"
              rm -rf "${DC_LOCAL_DIR:?}/"* "${DC_UPDATE_DIR:?}/"* || true

              FRESH_SECS=$(( ${DC_FRESH_HOURS:-24} * 3600 ))
              DB_PATH=""
              if [ -e "${DC_CACHE_DIR}/odc.mv.db" ]; then DB_PATH="${DC_CACHE_DIR}/odc.mv.db"; elif [ -e "${DC_CACHE_DIR}/cve.db" ]; then DB_PATH="${DC_CACHE_DIR}/cve.db"; fi

              IS_FRESH=0
              if [ -n "$DB_PATH" ]; then AGE=$(( $(date +%s) - $(stat -c %Y "$DB_PATH") )); [ $AGE -lt $FRESH_SECS ] && IS_FRESH=1; fi

              if [ $IS_FRESH -eq 0 ]; then
                echo ">>> Updating NVD DB..."
                set +e
                timeout 25m mvn -B org.owasp:dependency-check-maven:update-only \
                  -DnvdApiKey="${NVD_API_KEY}" -DdataDirectory="${DC_UPDATE_DIR}"
                RC=$?; set -e
                if [ $RC -eq 0 ] && { [ -e "${DC_UPDATE_DIR}/odc.mv.db" ] || [ -e "${DC_UPDATE_DIR}/cve.db" ]; }; then
                  rm -rf "${DC_CACHE_DIR:?}/"* || true
                  cp -R "${DC_UPDATE_DIR}/." "${DC_CACHE_DIR}/"
                fi
              fi

              if [ ! -e "${DC_CACHE_DIR}/odc.mv.db" ] && [ ! -e "${DC_CACHE_DIR}/cve.db" ]; then
                echo "No NVD DB; skipping Dependency-Check."; exit 0
              fi

              cp -R "${DC_CACHE_DIR}/." "${DC_LOCAL_DIR}/" || true
              rm -f "${DC_LOCAL_DIR}/odc.update.lock" || true

              mvn -B org.owasp:dependency-check-maven:check \
                 -DnvdApiKey="${NVD_API_KEY}" -DdataDirectory="${DC_LOCAL_DIR}" \
                 -DautoUpdate=false -DnvdValidForHours=${DC_FRESH_HOURS} -DfailOnCVSS=11 -DskipTests \
                 -Daggregate -Dformats=HTML,JSON || true
            '''
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'target/dependency-check-report.*', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: 'target', reportFiles: 'dependency-check-report.html', reportName: 'OWASP Dependency-Check Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        script {
          env.IMAGE_TAG = "${env.BUILD_NUMBER}"
        }
        sh '''
          set -e
          docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
          docker images "${IMAGE_NAME}:${IMAGE_TAG}" || true
        '''
      }
    }

    stage('Container Scan (Trivy)') {
      steps {
        sh '''
          set -e
          mkdir -p "${TRIVY_CACHE_DIR}" reports
          WORKDIR="$(pwd)"
          docker pull "aquasec/trivy:v${TRIVY_VER}" >/dev/null

          # Image scan
          docker run --rm \
            -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "${WORKDIR}:/workspace" -w /workspace \
            aquasec/trivy:v${TRIVY_VER} image \
              --scanners vuln --severity "${TRIVY_SEVERITY}" \
              $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
              --format json --output trivy-image.json \
              --timeout 10m "${IMAGE_NAME}:${IMAGE_TAG}" || true

          # Table summary
          docker run --rm \
            -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy" \
            -v /var/run/docker.sock:/var/run/docker.sock \
            -v "${WORKDIR}:/workspace" -w /workspace \
            aquasec/trivy:v${TRIVY_VER} image \
              --scanners vuln --severity "${TRIVY_SEVERITY}" \
              --format table --output trivy-summary.txt \
              --timeout 10m "${IMAGE_NAME}:${IMAGE_TAG}" || true

          # SBOM (if available)
          SBOM_PATH="target/bom.json"; [ -f "$SBOM_PATH" ] || SBOM_PATH="bom.json"
          if [ -f "$SBOM_PATH" ]; then
            docker run --rm \
              -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy" \
              -v "${WORKDIR}:/workspace" -w /workspace \
              aquasec/trivy:v${TRIVY_VER} sbom \
                --scanners vuln --severity "${TRIVY_SEVERITY}" \
                --format json --output trivy-sbom.json \
                --timeout 10m "$SBOM_PATH" || true
          fi

          # Pick final report
          if [ -s trivy-sbom.json ]; then cp trivy-sbom.json trivy-report.json; else cp trivy-image.json trivy-report.json || true; fi
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'trivy-*.*', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: '.', reportFiles: 'trivy-summary.html', reportName: 'Trivy — Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
        }
      }
    }

    stage('IaC Scan (Checkov)') {
      steps {
        sh '''
          set -e
          mkdir -p reports/checkov
          WORKDIR="$(pwd)"
          docker run --rm -v "${WORKDIR}:/project" -w /project bridgecrew/checkov:latest \
            -d /project/infra -o json --output-file-path ./reports/checkov,checkov.json || true
          docker run --rm -v "${WORKDIR}:/project" -w /project bridgecrew/checkov:latest \
            -d /project/infra -o html --output-file-path ./reports/checkov,checkov.html || true
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'reports/checkov/*', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: 'reports/checkov', reportFiles: 'checkov.html', reportName: 'Checkov — IaC Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
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
