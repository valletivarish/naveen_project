pipeline {
    agent any

    tools {
        maven 'Maven3'
        jdk 'JDK17'
    }

    environment {
        SONAR_TOKEN_ID = 'SONAR_TOKEN'
    }

    stages {
        stage('Checkout Code') {
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
    }

    post {
        success {
            archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
            echo "Build & Sonar completed successfully."
        }
        failure {
            echo "Build or Sonar failed — check the console output."
        }
    }
}
