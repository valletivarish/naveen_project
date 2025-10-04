pipeline {
    agent any

    tools {
        maven 'Maven3'   // Ensure "Maven3" is configured in Manage Jenkins → Global Tool Configuration
        jdk 'JDK17'      // Ensure "JDK17" is configured there too
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
                sh 'mvn -B -DskipTests clean package'
            }
        }
    }

    post {
        success {
            archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
        }
    }
}
