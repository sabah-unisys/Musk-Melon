// ==============================================================================
// Jenkins Multibranch Pipeline for Unisys MCP files (Musk-Melon repo)
//
// Trigger model : Pull-request only, via periodic repo scan (no webhook needed).
//                 Configure in the Multibranch job:
//                   - Branch Sources > GitHub > Behaviours:
//                         "Discover pull requests from origin"
//                            Strategy: "The current pull request revision"
//                   - Scan Repository Triggers > [x] Periodically if not
//                         otherwise run  ->  e.g. 2 minutes   (this is the poll)
//
// What it does  : ci/changed-files.sh  - list changed MCP files -> changed_files.txt
//                 ci/show-changes.sh    - per-file changes in the build log
//                 ci/diff-report.sh     - styled HTML diff report (HTML Publisher)
//                 All logic lives in the ci/ scripts; this file just orchestrates.
//
// Deployment    : add a 'Deploy' stage where indicated below.
// ==============================================================================

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
    }

    environment {
        DEFAULT_TARGET = 'master'                       // fallback target branch
        MCP_EXTENSIONS = 'c74_m c85_m das_m dat_m'    // tracked extensions (case-insensitive)
    }

    stages {

        stage('Not a PR - skip') {
            when { not { changeRequest() } }
            steps {
                echo 'Not a pull request - this pipeline only runs for PRs.'
            }
        }

        stage('Checkout') {
            when { changeRequest() }
            steps { checkout scm }
        }

        stage('Changed MCP files') {
            when { changeRequest() }
            steps { sh 'bash ci/changed-files.sh' }
        }

        stage('Show changes (log)') {
            when { changeRequest() }
            steps { sh 'bash ci/show-changes.sh' }
        }

        stage('HTML diff report') {
            when { changeRequest() }
            steps {
                sh 'bash ci/diff-report.sh > "pr_${CHANGE_ID}_diff_report.html"'
                publishHTML(target: [
                    reportName           : 'MCP PR Diff',
                    reportDir            : '.',
                    reportFiles          : "pr_${env.CHANGE_ID}_diff_report.html",
                    keepAll              : true,
                    alwaysLinkToLastBuild: true,
                    allowMissing         : true
                ])
            }
        }
        stage('Ensure Z: network drive') {
            when { changeRequest() }
            // agent { label 'windows' }   // uncomment if 'agent any' might land on a non-Windows node
            steps {
                // Drive mapping to a server almost always needs auth — store these as a
                // Jenkins "Username with password" credential and reference its ID here.
                echo "inside network drive creation stage"
                withCredentials([usernamePassword(credentialsId: 'z-drive-creds',
                                                usernameVariable: 'ZUSER',
                                                passwordVariable: 'ZPASS')]) {
                    bat '''
                        net use Z: >nul 2>&1
                        if %ERRORLEVEL%==0 (
                            echo Z: is already mapped - reusing existing connection.
                        ) else (
                            echo Z: not present - mapping to \\\\192.168.16.5 ...
                            net use Z: \\\\192.168.16.5\\_HOME_ %ZPASS% /user:%ZUSER% /persistent:no
                        )
                    '''
                }
            }
        }

        // ----------------------------------------------------------------------
        // stage('Deploy') {
        //     when { changeRequest() }
        //     steps { echo 'Deploy MCP files to target environment...' }
        // }
        // ----------------------------------------------------------------------
    }

    post {
        always {
            script {
                if (env.CHANGE_ID) {
                    archiveArtifacts artifacts: 'changed_files.txt, pr_*_changes.txt, pr_*_diff_report.html',
                                     allowEmptyArchive: true,
                                     fingerprint: true
                }
            }
        }
    }
}
