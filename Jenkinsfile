pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Build') {
            steps {
                // Replace with your build command
                sh 'echo "Building the project..."'
            }
        }
        stage('Test') {
            steps {
                // Replace with your test command
                sh 'echo "Running tests..."'
            }
        }
    }
    post {
        success {
            echo 'Validation succeeded.'
        }
        failure {
            echo 'Validation failed.'
        }
    }
}
