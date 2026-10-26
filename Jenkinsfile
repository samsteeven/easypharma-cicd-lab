// Pipeline déclaratif du backend EasyPharma. Les étapes (mavenBuild, sonarScan, dockerBuildPush) viennent de la
// bibliothèque partagée « easypharma-lib » : dossier vars/ de ce dépôt.
@Library('easypharma-lib') _

pipeline {
    agent any

    options {
        timestamps()
        ansiColor('xterm')
        timeout(time: 30, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    parameters {
        string(name: 'APP_REPO', defaultValue: 'https://github.com/samsteeven/easypharma-backend-lab.git', description: 'Dépôt de l\'application')
        string(name: 'APP_BRANCH', defaultValue: 'main', description: 'Branche à construire')
        booleanParam(name: 'RUN_SONAR', defaultValue: true, description: 'Analyser avec SonarQube et attendre la porte qualité')
        booleanParam(name: 'BLOQUER', defaultValue: true, description: 'Bloquer la publication si une faille CRITIQUE corrigible est trouvée dans cette image (décocher = dérogation consciente)')
        booleanParam(name: 'PUSH_IMAGE', defaultValue: true, description: 'Publier l\'image dans le registre local')
    }

    environment {
        IMAGE_NAME = 'easypharma-backend'
        REGISTRY   = 'localhost:5001'
    }

    stages {
        stage('Récupération du code') {
            steps {
                git url: params.APP_REPO, branch: params.APP_BRANCH
                script {
                    env.GIT_SHORT = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
                    env.IMAGE_TAG = "${env.GIT_SHORT}-${env.BUILD_NUMBER}"
                }
                echo "Commit ${env.GIT_SHORT}, étiquette d'image ${env.IMAGE_TAG}"
            }
        }

        stage('Build et tests') {
            steps {
                mavenBuild()
            }
            post {
                always {
                    junit testResults: 'target/surefire-reports/*.xml', allowEmptyResults: true
                    archiveArtifacts artifacts: 'target/site/jacoco/jacoco.xml', allowEmptyArchive: true
                }
            }
        }

        // Contrôles de sécurité en parallèle (voir vars/securityScan.groovy). Non exécutés dans ce laboratoire : le README
        // dit ce qui a tourné pour de vrai (GitHub Actions) et ce qui a seulement été écrit.
        stage('Sécurité') {
            parallel {
                stage('Secrets') { steps { securityScan(check: 'secrets') } }
                stage('Dépendances') { steps { securityScan(check: 'dependances') } }
                stage('Dockerfile') { steps { securityScan(check: 'dockerfile') } }
            }
        }

        stage('SonarQube') {
            when { expression { params.RUN_SONAR } }
            steps {
                sonarScan(projectKey: 'easypharma_backend', projectName: 'EasyPharma backend')
            }
        }

        stage('Porte qualité') {
            when { expression { params.RUN_SONAR } }
            steps {
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        stage('Image Docker') {
            when { expression { params.PUSH_IMAGE } }
            steps {
                dockerBuildPush(image: env.IMAGE_NAME, registry: env.REGISTRY, tag: env.IMAGE_TAG, scan: true, block: params.BLOQUER)
            }
        }
    }

    post {
        success { echo "Pipeline réussi : ${env.REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}" }
        failure { echo 'Pipeline en échec : voir l\'étape en rouge ci-dessus.' }
        cleanup { cleanWs(deleteDirs: true, notFailBuild: true) }
    }
}
