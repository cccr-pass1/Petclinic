pipeline {
    agent any 
    
    tools {
        jdk 'jdk-17'
        maven 'maven-3.9'
    }
    
    environment {
        SCANNER_HOME = tool 'sonar-scanner'
        TOMCAT_HOST = 'http://3.35.47.25'  // Tomcat 서버 호스트
        TOMCAT_PORT = '8080'  // Tomcat 관리 포트
        TOMCAT_USER = credentials('deployer_user')  // Jenkins에 설정된 Tomcat 인증 정보
    }
    
    parameters {
        choice choices: ['Baseline', 'APIS', 'Full'],
            description: 'Type of scan that is going to perform inside the container',
            name: 'SCAN_TYPE'

        string defaultValue: 'http://3.35.47.25:8080/petclinic/',
            description: 'Target URL to scan',
            name: 'TARGET'

        booleanParam defaultValue: true,
            description: 'Parameter to know if you want to generate a report.',
            name: 'GENERATE_REPORT'
    }
    
    stages {
        
        stage("Git Checkout") {
            steps {
                git branch: 'main', changelog: false, poll: false, url: 'https://github.com/cccr-pass1/Petclinic.git'
            }
        }
        
        stage('Build') {
            steps {
                sh 'mvn clean package -DskipTests'
            }
        }
        
        stage('Run Sonarqube') {
            steps {
                withSonarQubeEnv(credentialsId: 'jenkins_sonar', installationName: 'sonar-server') {
                    sh """
                        ${tool('sonar-scanner')}/bin/sonar-scanner \
                        -Dsonar.projectKey=jyk \
                        -Dsonar.sources=. \
                        -Dsonar.java.binaries=target/classes \
                        -Dsonar.host.url=${SONAR_HOST_URL} \
                        -Dsonar.login=${SONAR_AUTH_TOKEN}
                    """
                }
            }
        }
        
        stage("OWASP Dependency Check") {
            steps {
                dependencyCheck additionalArguments: '--scan ./ ', odcInstallation: 'DP-Check'
                dependencyCheckPublisher pattern: '**/dependency-check-report.xml'
            }
        }
        
        stage('Deploy to Tomcat') {
            steps {
                script {
                    echo "Deploying WAR file to Tomcat"
                    echo "WAR file path: ${WORKSPACE}/target/petclinic.war"
                    echo "Tomcat URL: ${TOMCAT_HOST}:${TOMCAT_PORT}"
                    
                    def deployResult = deploy adapters: [tomcat9(credentialsId: 'deployer_user', 
                                              path: '', 
                                              url: "${TOMCAT_HOST}:${TOMCAT_PORT}")], 
                           contextPath: 'petclinic', 
                           war: 'target/petclinic.war'
                    
                    echo "Deploy result: ${deployResult}"
                }
            }
        }

        stage('Setting up OWASP ZAP docker container') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'dockerhub_jenkins', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                    sh 'docker login -u $DOCKER_USER -p $DOCKER_PASS'
                }
                echo 'Pulling up last OWASP ZAP container --> Start'
                sh 'docker pull zaproxy/zap-stable'
                echo 'Pulling up last VMS container --> End'
                echo 'Starting container --> Start'
                sh 'docker run -dt --name owasp zaproxy/zap-stable /bin/bash'
            }
        }

        stage('Prepare wrk directory') {
            when {
                environment name : 'GENERATE_REPORT', value: 'true'
            }
            steps {
                script {
                    sh 'docker exec owasp mkdir /zap/wrk'
                }
            }
        }

        stage('Scanning target on owasp container') {
            steps {
                script {
                    scan_type = "${params.SCAN_TYPE}"
                    target = "${params.TARGET}"
                    if (scan_type == 'Baseline') {
                        sh """
                            docker exec owasp \
                            zap-baseline.py \
                            -t $target \
                            -r report.html \
                            -I
                        """
                    } else if (scan_type == 'APIS') {
                        sh """
                            docker exec owasp \
                            zap-api-scan.py \
                            -t $target \
                            -r report.html \
                            -I
                        """
                    } else if (scan_type == 'Full') {
                        sh """
                            docker exec owasp \
                            zap-full-scan.py \
                            -t $target \
                            -r report.html \
                            -I
                        """
                    } else {
                        echo 'Something went wrong...'
                    }
                }
            }
        }

        stage('Copy Report to Workspace') {
            steps {
                script {
                    sh 'docker cp owasp:/zap/wrk/report.html ${WORKSPACE}/report.html'
                }
            }
        }

        // Petclinic Docker 이미지 빌드 및 Docker Hub 푸시
        stage('Build and Push Docker Image for Petclinic') {
            steps {
                script {
                    echo "Building Docker image for Petclinic"
                    withCredentials([usernamePassword(credentialsId: 'dockerhub_jenkins', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        // Docker login
                        sh 'docker login -u $DOCKER_USER -p $DOCKER_PASS'
                
                        // Docker build
                        sh 'docker build -t nuitciel/petclinic:latest .'
                
                        // Docker push
                        sh 'docker push nuitciel/petclinic:latest'
                    }
                }
            }
        }

        // Docker 이미지에 대한 Trivy 스캔
        stage('Trivy Docker Image Scan') {
            steps {
                script {
                    // Docker Hub에서 Petclinic 이미지 풀
                    withCredentials([usernamePassword(credentialsId: 'dockerhub_jenkins', usernameVariable: 'DOCKER_USER', passwordVariable: 'DOCKER_PASS')]) {
                        sh 'docker login -u $DOCKER_USER -p $DOCKER_PASS'
                        sh 'docker pull nuitciel/petclinic:latest'
                    }
                    
                    sh "trivy image --severity CRITICAL --no-progress nuitciel/petclinic:latest > trivy_report.txt"
                }
            }
        }
        
        stage('Email Report') {
            steps {
                emailext (
                    attachLog: true,
                    attachmentsPattern: '**/*.html, **/trivy_report.txt', // Trivy 리포트 파일 추가
                    body: "Please find the attached reports for the latest OWASP ZAP Scan and Trivy scan.",
                    recipientProviders: [buildUser()],
                    subject: "OWASP ZAP and Trivy Scan Reports",
                    to: 'nuitciel99@gmail.com'
                )
            }
        }
    }
    
    post {
        always {
            echo 'Removing container'
            sh 'docker stop owasp && docker rm owasp'
            cleanWs()
        }
    }
}
