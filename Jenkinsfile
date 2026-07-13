// ==============================================================================
// Jenkins Multibranch Pipeline for Unisys MCP files (Musk-Melon repo)
//
// Trigger model : Pull-request + master, via periodic repo scan (no webhook needed).
//                 Configure in the Multibranch job:
//                   - Branch Sources > GitHub > Behaviours:
//                         "Discover pull requests from origin"
//                            Strategy: "The current pull request revision"
//                         "Discover branches"            (required for the master build)
//                   - Scan Repository Triggers > [x] Periodically if not
//                         otherwise run  ->  e.g. 2 minutes   (this is the poll)
//
// CI (on PRs)   : ci/changed-files.sh  - list changed MCP files -> changed_files.txt
//                 ci/show-changes.sh    - per-file changes in the build log
//                 ci/diff-report.sh     - styled HTML diff report (HTML Publisher)
//                 ci/compare-report.ps1 - PR files vs the Z: copies (mcpcopy)
//
// CD (on master): ci/backup.ps1     - generate + copy + start the backup WFL
//                 ci/deploy.ps1      - mcpcopy merged files to Z:
//                 ci/compile-wfl.ps1 - generate + copy + start the compile WFL
//                 The GitHub merge is the approval gate: CD runs automatically
//                 on the master build that fires after a PR is merged.
// ==============================================================================

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
    }

    environment {
        DEFAULT_TARGET = 'master'                       // fallback target branch
        MCP_EXTENSIONS = 'c74_m c85_m das_m dat_m wfl_m'    // tracked extensions (case-insensitive)
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

        stage('Compare with Z: (mcpcopy)') {
            when { changeRequest() }
    // agent { label 'windows' }   // this node needs Z: mapped + mcpcopy.exe on PATH
            steps {
                bat 'powershell -NoProfile -ExecutionPolicy Bypass -File ci\\compare-report.ps1'
                publishHTML(target: [
                    reportName           : 'MCP vs Z: Diff',
                    reportDir            : '.',
                    reportFiles          : "pr_${env.CHANGE_ID}_z_diff_report.html",
                    keepAll              : true,
                    alwaysLinkToLastBuild: true,
                    allowMissing         : true
                ])
            }
        }

        // ----------------------------------------------------------------------
        // CD: runs automatically on the master build (i.e. after a PR is merged).
        //     The GitHub merge is the approval gate — no manual input prompt.
        // ----------------------------------------------------------------------
        stage('Backup') {
            when { branch 'master' }
            // agent { label 'windows' }      // needs Z: mapped + mcpcopy.exe on PATH
            steps {
                // Runs before Deploy so the current MCP files can be backed up
                // before they are overwritten. The PR-only 'Checkout' stage above
                // does not run on the master build, so check out the source here
                // to make ci\backup.ps1 available in the workspace.
                checkout scm
                bat 'powershell -NoProfile -ExecutionPolicy Bypass -File ci\\backup.ps1'
                archiveArtifacts artifacts: 'BACKUPCOPY.wfl_m',
                                 allowEmptyArchive: true,
                                 fingerprint: true
            }
        }
        stage('Deploy to MCP') {
            when { branch 'master' }
            // agent { label 'windows' }      // needs Z: mapped + mcpcopy.exe on PATH
            steps {
                // Clean workspace
                cleanWs()
                // The PR-only 'Checkout' stage above does not run on the master
                // build, so check out the merged source here before deploying.
                checkout scm
                bat 'powershell -NoProfile -ExecutionPolicy Bypass -File ci\\deploy.ps1'
                archiveArtifacts artifacts: 'deployed_files.txt, changed_files.txt',
                                 allowEmptyArchive: true,
                                 fingerprint: true
            }
        }

        stage('Compile COBOL on MCP') {
            when { branch 'master' }
            // agent { label 'windows' }      // same Windows node as Deploy
            steps {
                // Uses changed_files.txt written by deploy.ps1 in this workspace.
                // bat 'echo CWD=%CD% & dir /b & if exist ci (dir /b ci) else (echo NO ci FOLDER)'
                bat 'powershell -NoProfile -ExecutionPolicy Bypass -File ci\\compile-wfl.ps1'
                archiveArtifacts artifacts: 'compile_*.wfl_m',
                                 allowEmptyArchive: true,
                                 fingerprint: true
            }
        }

        stage('WFL syntax check') {
            when { branch 'master' }
            // agent { label 'windows' }      // same Windows node as Deploy
            steps {
                // Uses changed_files.txt written by deploy.ps1 in this workspace.
                // Generates a syntax-check WFL for every changed .wfl_m, copies it
                // to Z:\INSTALLWFL\SYNTAX<PR>, and starts it via the WFLX pipe.
                bat 'powershell -NoProfile -ExecutionPolicy Bypass -File ci\\syntaxcheck-wfl.ps1'
                archiveArtifacts artifacts: 'syntaxcheck_*.wfl_m',
                                 allowEmptyArchive: true,
                                 fingerprint: true
            }
        }
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
