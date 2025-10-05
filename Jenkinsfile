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
            echo "Using SonarQube: $SURL"
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
              mkdir -p "${DC_CACHE_DIR}"
              rm -rf "${DC_LOCAL_DIR}" "${DC_UPDATE_DIR}"
              mkdir -p "${DC_LOCAL_DIR}" "${DC_UPDATE_DIR}"

              FRESH_SECS=$(( ${DC_FRESH_HOURS:-24} * 3600 ))
              DB_PATH=""
              if [ -e "${DC_CACHE_DIR}/odc.mv.db" ]; then DB_PATH="${DC_CACHE_DIR}/odc.mv.db"; elif [ -e "${DC_CACHE_DIR}/cve.db" ]; then DB_PATH="${DC_CACHE_DIR}/cve.db"; fi

              IS_FRESH=0
              if [ -n "$DB_PATH" ]; then AGE=$(( $(date +%s) - $(stat -c %Y "$DB_PATH") )); [ $AGE -lt $FRESH_SECS ] && IS_FRESH=1; fi

              if [ $IS_FRESH -eq 0 ]; then
                set +e
                timeout 25m sh -c 'mvn -B org.owasp:dependency-check-maven:update-only -DnvdApiKey='"${NVD_API_KEY}"' -DdataDirectory="'"${DC_UPDATE_DIR}"'"'
                RC=$?; set -e
                if [ $RC -eq 0 ] && { [ -e "${DC_UPDATE_DIR}/odc.mv.db" ] || [ -e "${DC_UPDATE_DIR}/cve.db" ]; }; then
                  rm -rf "${DC_CACHE_DIR:?}/"* || true
                  cp -R "${DC_UPDATE_DIR}/." "${DC_CACHE_DIR}/"
                fi
              fi

              if [ ! -e "${DC_CACHE_DIR}/odc.mv.db" ] && [ ! -e "${DC_CACHE_DIR}/cve.db" ]; then
                echo "No NVD DB; skipping Dependency-Check."; exit 0
              fi

              rm -rf "${DC_LOCAL_DIR:?}/"* || true
              cp -R "${DC_CACHE_DIR}/." "${DC_LOCAL_DIR}/" || true
              rm -f "${DC_LOCAL_DIR}/odc.update.lock" || true

              mvn -B org.owasp:dependency-check-maven:check \
                 -DnvdApiKey='${NVD_API_KEY}' -DdataDirectory="${DC_LOCAL_DIR}" \
                 -DautoUpdate=false -DnvdValidForHours=${DC_FRESH_HOURS} -DfailOnCVSS=11 -DskipTests \
                 -Daggregate -Dformats=HTML,JSON

              if [ -f target/dependency-check-report.json ]; then
                echo ">>> Sanity check: searching for vulnerable libs in JSON"
                grep -E -i 'log4j-core|commons-collections' target/dependency-check-report.json || echo "Not found in JSON"
              fi
            '''
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'target/dependency-check-report.html,target/dependency-check-report.json', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: 'target', reportFiles: 'dependency-check-report.html', reportName: 'OWASP Dependency-Check Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
        }
      }
    }

    stage('Build Docker Image') {
      when { expression { sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0 } }
      steps {
        script {
          env.IMAGE_TAG = "${env.BUILD_NUMBER}"
        }
        sh '''
          set -e
          echo "Building image ${IMAGE_NAME}:${IMAGE_TAG}"
          docker build -t "${IMAGE_NAME}:${IMAGE_TAG}" .
          docker images "${IMAGE_NAME}:${IMAGE_TAG}" || true
        '''
      }
    }

    stage('Container Scan (Trivy in Docker)') {
      when { expression { sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0 } }
      steps {
        script {
          env.IMAGE_TAG = env.IMAGE_TAG ?: "${env.BUILD_NUMBER}"
        }
        sh '''
          set -e
          mkdir -p "${TRIVY_CACHE_DIR}"
          mkdir -p reports
          docker pull "aquasec/trivy:v${TRIVY_VER}" >/dev/null
          WORKDIR="$(pwd)"
          docker run --rm \
            -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy" \
            -v "/var/run/docker.sock:/var/run/docker.sock" \
            -v "${WORKDIR}:/workspace" -w /workspace \
            "aquasec/trivy:v${TRIVY_VER}" image \
              --scanners vuln \
              --severity "${TRIVY_SEVERITY}" \
              $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
              --format json --output trivy-image.json \
              --timeout 10m \
              "${IMAGE_NAME}:${IMAGE_TAG}" || true
          docker run --rm \
            -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy" \
            -v "/var/run/docker.sock:/var/run/docker.sock" \
            -v "${WORKDIR}:/workspace" -w /workspace \
            "aquasec/trivy:v${TRIVY_VER}" image \
              --scanners vuln \
              --severity "${TRIVY_SEVERITY}" \
              $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
              --format table --output trivy-summary.txt \
              --timeout 10m \
              "${IMAGE_NAME}:${IMAGE_TAG}" || true
          if [ ! -f target/bom.json ] && [ -f pom.xml ]; then
            mvn -B org.cyclonedx:cyclonedx-maven-plugin:2.8.0:makeAggregateBom \
              -DskipTests -Dcyclonedx.output.format=json \
              -Dcyclonedx.output.name=bom \
              -Dcyclonedx.includeBomSerialNumber=true \
              -Dcyclonedx.include.components=true \
              -Dcyclonedx.include.dependencies=true || true
          fi
          SBOM_PATH="target/bom.json"; [ -f "$SBOM_PATH" ] || SBOM_PATH="bom.json"
          if [ -f "$SBOM_PATH" ]; then
            docker run --rm \
              -v "${TRIVY_CACHE_DIR}:/root/.cache/trivy" \
              -v "${WORKDIR}:/workspace" -w /workspace \
              "aquasec/trivy:v${TRIVY_VER}" sbom \
                --scanners vuln \
                --severity "${TRIVY_SEVERITY}" \
                $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
                --format json --output trivy-sbom.json \
                --timeout 10m \
                "$SBOM_PATH" || true
          fi
          if [ -s trivy-sbom.json ]; then cp trivy-sbom.json trivy-report.json; else cp trivy-image.json trivy-report.json || true; fi
          if [ -s trivy-report.json ]; then
            docker run --rm \
              -v "${WORKDIR}:/workspace" -w /workspace \
              "aquasec/trivy:v${TRIVY_VER}" convert --format sarif --output trivy-report.sarif trivy-report.json || true
          fi
          TOTAL=$(jq -r '.. | .Vulnerabilities? // empty | length' trivy-report.json 2>/dev/null | awk '{s+=$1} END{print s+0}' || echo 0)
          HIGH=$(jq -r '.. | .Severity? // empty' trivy-report.json 2>/dev/null | grep -c '^HIGH$' || true)
          CRIT=$(jq -r '.. | .Severity? // empty' trivy-report.json 2>/dev/null | grep -c '^CRITICAL$' || true)
          {
            echo "<html><head><meta charset='utf-8'><style>body{font-family:ui-sans-serif,system-ui,Segoe UI,Roboto,Arial} table{border-collapse:collapse;width:100%} th,td{border:1px solid #ddd;padding:6px} th{background:#f3f4f6;text-align:left}</style></head><body>"
            echo "<h2>Trivy Summary (Image & SBOM)</h2>"
            echo "<p><b>Total</b>: ${TOTAL} &nbsp; <b>Critical</b>: ${CRIT} &nbsp; <b>High</b>: ${HIGH}</p>"
            echo "<pre>"
            sed -e 's/&/\\&amp;/g' -e 's/</\\&lt;/g' trivy-summary.txt 2>/dev/null || true
            echo "</pre>"
            echo "</body></html>"
          } > trivy-summary.html
        '''
      }
      post {
        always {
          archiveArtifacts artifacts: 'trivy-report.json,trivy-image.json,trivy-sbom.json,trivy-report.sarif,trivy-summary.txt,trivy-summary.html', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: '.', reportFiles: 'trivy-summary.html', reportName: 'Trivy — Full Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
        }
      }
    }

    stage('IaC Scan (Checkov)') {
      when { expression { sh(script: 'command -v docker >/dev/null 2>&1', returnStatus: true) == 0 } }
      steps {
        sh '''
          set -e
          mkdir -p reports/checkov
          WORKDIR="$(pwd)"
          docker run --rm -v "${WORKDIR}:/project" -w /project bridgecrew/checkov:latest \
            -d /project/infra -o json --output-file-path ./reports/checkov,checkov.json || true
          docker run --rm -v "${WORKDIR}:/project" -w /project bridgecrew/checkov:latest \
            -d /project/infra -o sarif --output-file-path ./reports/checkov,checkov.sarif || true
          docker run --rm -v "${WORKDIR}:/project" -w /project bridgecrew/checkov:latest \
            -d /project/infra -o junitxml --output-file-path ./reports/checkov,checkov-junit.xml || true
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
