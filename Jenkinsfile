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
                 -DautoUpdate=false -DnvdValidForHours=${DC_FRESH_HOURS} -DfailOnCVSS=11 -DskipTests
            '''
          }
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'target/dependency-check-report.html', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: 'target', reportFiles: 'dependency-check-report.html', reportName: 'OWASP Dependency-Check Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
        }
      }
    }

    stage('Container Build & Scan (Trivy)') {
      steps {
        script {
          def imgTag = "petclinic-app:${env.BUILD_NUMBER}"
          sh '''
            set -e
            mkdir -p "${TRIVY_CACHE_DIR}"
            TRIVY_BIN="./trivy"
            if ! [ -x "$TRIVY_BIN" ]; then
              curl -sSL -o trivy.tgz "https://github.com/aquasecurity/trivy/releases/download/v${TRIVY_VER}/trivy_${TRIVY_VER}_Linux-64bit.tar.gz"
              tar -xzf trivy.tgz trivy && chmod +x trivy
            fi
            if ! command -v jq >/dev/null 2>&1; then
              curl -sSL -o jq https://github.com/stedolan/jq/releases/download/jq-1.6/jq-linux64 || curl -sSL -o jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux-amd64
              chmod +x jq
              JQ="./jq"
            else
              JQ="jq"
            fi

            TARGET_FILE="$(ls target/*.jar 2>/dev/null | head -n1 || true)"; [ -z "$TARGET_FILE" ] && TARGET_FILE="."
            NOW=$(date +%s); FRESH_SECS=$(( ${TRIVY_FRESH_HOURS:-12} * 3600 ))
            META="${TRIVY_CACHE_DIR}/db/metadata.json"; SKIP_ARGS=""

            if [ -f "$META" ]; then AGE=$(( NOW - $(stat -c %Y "$META") )); [ $AGE -lt $FRESH_SECS ] && SKIP_ARGS="--skip-db-update --offline-scan"; fi
            [ -n "$SKIP_ARGS" ] && echo "Trivy cache fresh; using ${SKIP_ARGS}." || echo "No/old cache; first scan may download DB."

            if command -v docker >/dev/null 2>&1; then
              echo ">>> Docker detected. Building image and scanning."
              docker build -t '"${imgTag}"' .
              docker images '"${imgTag}"' || true

              "$TRIVY_BIN" image --cache-dir "${TRIVY_CACHE_DIR}" ${SKIP_ARGS} \
                --scanners vuln --severity "${TRIVY_SEVERITY}" $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
                --timeout 10m --format json --output trivy-report.json '"${imgTag}"' || true

              "$TRIVY_BIN" image --cache-dir "${TRIVY_CACHE_DIR}" ${SKIP_ARGS} \
                --scanners vuln --severity "${TRIVY_SEVERITY}" $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
                --timeout 10m --format table --output trivy-summary.txt '"${imgTag}"' || true
            else
              echo ">>> Docker not found. Scanning build artifacts."
              "$TRIVY_BIN" fs --cache-dir "${TRIVY_CACHE_DIR}" ${SKIP_ARGS} \
                --scanners vuln --severity "${TRIVY_SEVERITY}" $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
                --timeout 10m --format json --output trivy-report.json "$TARGET_FILE" || true

              "$TRIVY_BIN" fs --cache-dir "${TRIVY_CACHE_DIR}" ${SKIP_ARGS} \
                --scanners vuln --severity "${TRIVY_SEVERITY}" $( [ "${TRIVY_IGNORE_UNFIXED}" = "true" ] && echo --ignore-unfixed ) \
                --timeout 10m --format table --output trivy-summary.txt "$TARGET_FILE" || true
            fi

            if [ -s trivy-report.json ]; then
              "$TRIVY_BIN" convert --format sarif --output trivy-report.sarif trivy-report.json || true
            fi

            HIGH=0; CRIT=0; TOTAL=0
            if [ -s trivy-report.json ]; then
              HIGH=$($JQ -r '.. | .Severity? // empty' trivy-report.json | grep -c '^HIGH$' || true)
              CRIT=$($JQ -r '.. | .Severity? // empty' trivy-report.json | grep -c '^CRITICAL$' || true)
              TOTAL=$($JQ -r '.. | .Vulnerabilities? // empty | length' trivy-report.json | awk '{s+=$1} END{print s+0}' || echo 0)
            fi

            if [ ! -s trivy-summary.txt ]; then
              {
                echo "No table output from Trivy."
                echo "Findings (all severities): TOTAL=${TOTAL}, CRITICAL=${CRIT}, HIGH=${HIGH}"
                echo "Severity filter used: ${TRIVY_SEVERITY}  ignore-unfixed=${TRIVY_IGNORE_UNFIXED}"
                [ -n "$TARGET_FILE" ] && echo "Target: ${TARGET_FILE}"
              } > trivy-summary.txt
            fi

            {
              echo "<html><head><meta charset='utf-8'><style>body{font-family:ui-sans-serif,system-ui,Segoe UI,Roboto,Arial} table{border-collapse:collapse;width:100%} th,td{border:1px solid #ddd;padding:6px} th{background:#f3f4f6;text-align:left}</style></head><body>"
              echo "<h2>Trivy Summary</h2>"
              echo "<p><b>Total</b>: ${TOTAL} &nbsp; <b>Critical</b>: ${CRIT} &nbsp; <b>High</b>: ${HIGH}</p>"
              echo "<pre>"
              sed -e 's/&/\\&amp;/g' -e 's/</\\&lt;/g' trivy-summary.txt
              echo "</pre>"
              if [ -s trivy-report.json ]; then
                echo "<h3>Top Findings (${TRIVY_STRICT_SEV})</h3>"
                echo "<table><tr><th>Severity</th><th>ID</th><th>Pkg</th><th>Installed</th><th>Fixed</th><th>Title</th></tr>"
                $JQ -r --arg sev "${TRIVY_STRICT_SEV}" '
                  .Results[]?.Vulnerabilities[]? |
                  select((.Severity|tostring) as $s | ($sev|split(",")) | index($s)) |
                  [.Severity, .VulnerabilityID, .PkgName, .InstalledVersion, (.FixedVersion//"-"), (.Title//"-")]
                ' trivy-report.json 2>/dev/null | head -n 200 | awk -F'\t' 'BEGIN{OFS="</td><td>"} {gsub(/&/,"&amp;"); gsub(/</,"&lt;"); print "<tr><td>"$1,$2,$3,$4,$5,$6"</td></tr>"}'
                echo "</table>"
              fi
              echo "</body></html>"
            } > trivy-summary.html
          '''
        }
      }
      post {
        always {
          archiveArtifacts artifacts: 'trivy-report.json,trivy-report.sarif,trivy-summary.txt,trivy-summary.html', fingerprint: true, allowEmptyArchive: true
          publishHTML target: [reportDir: '.', reportFiles: 'trivy-summary.html', reportName: 'Trivy — Full Report', keepAll: true, alwaysLinkToLastBuild: true, allowMissing: true]
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
