pipeline {
  agent any

  environment {
    GITHUB_TOKEN      = credentials('github-token')
    GITHUB_REPO       = 'sabah-unisys/testrepo'
    GITHUB_ORG        = 'sabah-unisys'
    UNISYS_HOST       = credentials('unisys-host')
    UNISYS_USER       = credentials('unisys-user')
    UNISYS_PASS       = credentials('unisys-pass')
    CHANGED_FILES_DIR = "${WORKSPACE}/changed_files"
  }

  stages {

    // ── Stage 1 ────────────────────────────────────────────────────
    stage('Checkout') {
      steps {
        checkout scm
      }
    }

    // ── Stage 2 ────────────────────────────────────────────────────
    stage('Detect changed files') {
      steps {
        script {
          sh "mkdir -p ${CHANGED_FILES_DIR}"

          def changed = sh(
            script: """
              git diff --name-only HEAD~1 HEAD \
                | grep -E '\\.(c85_m|c74_m|wfl_m)\$' || true
            """,
            returnStdout: true
          ).trim()

          if (!changed) {
            echo "No COBOL or WFL files changed in this commit. Nothing to do."
            currentBuild.result = 'SUCCESS'
            return
          }

          echo "Changed mainframe files:\n${changed}"

          // write cobol and wfl text files
          sh """
            echo '${changed}' | grep -E '\\.(c85_m|c74_m)\$' > ${CHANGED_FILES_DIR}/cobol_files.txt || true
            echo '${changed}' | grep '\\.wfl_m\$'             > ${CHANGED_FILES_DIR}/wfl_files.txt   || true
          """

          sh """
            echo "--- cobol_files.txt ---"
            cat ${CHANGED_FILES_DIR}/cobol_files.txt || echo "(empty)"
            echo "--- wfl_files.txt ---"
            cat ${CHANGED_FILES_DIR}/wfl_files.txt   || echo "(empty)"
          """

          // ── generate HTML diff report ───────────────────────────
          sh """
            mkdir -p ${CHANGED_FILES_DIR}/diff_report
            cat > ${CHANGED_FILES_DIR}/diff_report/index.html << 'HTMLEOF'
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <title>Changed Files Diff Report</title>
  <style>
    body       { font-family: monospace; background: #1e1e1e; color: #d4d4d4; margin: 20px; }
    h1         { color: #569cd6; }
    h2         { color: #9cdcfe; border-bottom: 1px solid #444; padding-bottom: 6px; margin-top: 40px; }
    .meta      { color: #888; font-size: 0.85em; margin-bottom: 10px; }
    .diff-box  { background: #252526; border: 1px solid #444; border-radius: 4px;
                 padding: 12px; overflow-x: auto; white-space: pre; }
    .added     { color: #6a9955; background: #1a2f1a; display: block; }
    .removed   { color: #f44747; background: #2f1a1a; display: block; }
    .hunk      { color: #c586c0; display: block; }
    .context   { color: #d4d4d4; display: block; }
    .new-file  { color: #dcdcaa; background: #252526; border: 1px solid #444;
                 border-radius: 4px; padding: 12px; overflow-x: auto; white-space: pre; }
    .tag-new   { background: #0e639c; color: white; font-size: 0.75em;
                 padding: 2px 8px; border-radius: 10px; margin-left: 10px; }
    .tag-mod   { background: #5a4a00; color: #ffd700; font-size: 0.75em;
                 padding: 2px 8px; border-radius: 10px; margin-left: 10px; }
    .summary   { background: #252526; border: 1px solid #444; border-radius: 4px;
                 padding: 12px; margin-bottom: 30px; }
  </style>
</head>
<body>
  <h1>Changed Files — Diff Report</h1>
  <div class="summary">
    <strong>Branch:</strong> ${env.BRANCH_NAME} &nbsp;|&nbsp;
    <strong>Build:</strong> #${env.BUILD_NUMBER} &nbsp;|&nbsp;
    <strong>Commit:</strong> ${sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()}
  </div>
HTMLEOF
          """

          // per-file diff or new file content
          changed.split('\n').each { file ->
            def name = file.trim()
            if (!name) return

            def isNew = sh(
              script: "git show HEAD~1:${name} > /dev/null 2>&1 && echo 'existing' || echo 'new'",
              returnStdout: true
            ).trim() == 'new'

            if (isNew) {
              // new file — show full content
              def content = sh(
                script: "cat ${name} | sed 's/&/\\&amp;/g; s/</\\&lt;/g; s/>/\\&gt;/g'",
                returnStdout: true
              )
              sh """
                cat >> ${CHANGED_FILES_DIR}/diff_report/index.html << 'FILEEOF'
  <h2>${name} <span class="tag-new">NEW FILE</span></h2>
  <div class="meta">New file added in this commit</div>
  <div class="new-file">${content}</div>
FILEEOF
              """
            } else {
              // existing file — show colorized diff
              def rawDiff = sh(
                script: """
                  git diff HEAD~1 HEAD -- ${name} \
                    | sed 's/&/\\&amp;/g; s/</\\&lt;/g; s/>/\\&gt;/g' || true
                """,
                returnStdout: true
              )

              def colorizedDiff = rawDiff.split('\n').collect { line ->
                if      (line.startsWith('+') && !line.startsWith('+++')) return "<span class=\"added\">${line}</span>"
                else if (line.startsWith('-') && !line.startsWith('---')) return "<span class=\"removed\">${line}</span>"
                else if (line.startsWith('@@'))                            return "<span class=\"hunk\">${line}</span>"
                else                                                       return "<span class=\"context\">${line}</span>"
              }.join('\n')

              sh """
                cat >> ${CHANGED_FILES_DIR}/diff_report/index.html << 'FILEEOF'
  <h2>${name} <span class="tag-mod">MODIFIED</span></h2>
  <div class="meta">Diff: previous version → this commit</div>
  <div class="diff-box">${colorizedDiff}</div>
FILEEOF
              """
            }
          }

          // close HTML
          sh "echo '</body></html>' >> ${CHANGED_FILES_DIR}/diff_report/index.html"

          // archive text files as build artifacts
          archiveArtifacts artifacts: 'changed_files/*.txt', allowEmptyArchive: true

          // publish HTML diff report (requires HTML Publisher Plugin)
          publishHTML(target: [
            allowMissing:          false,
            alwaysLinkToLastBuild: true,
            keepAll:               true,
            reportDir:             "${CHANGED_FILES_DIR}/diff_report",
            reportFiles:           'index.html',
            reportName:            'Changed Files Diff Report',
            reportTitles:          'Diff Report'
          ])
        }
      }
    }

    // ── Stage 3 ────────────────────────────────────────────────────
    stage('Stage WFL files') {
      when {
        expression {
          fileExists("${CHANGED_FILES_DIR}/wfl_files.txt") &&
          readFile("${CHANGED_FILES_DIR}/wfl_files.txt").trim()
        }
      }
      steps {
        script {
          sh "mkdir -p artifacts"
          def wflFiles = readFile("${CHANGED_FILES_DIR}/wfl_files.txt").trim()
          wflFiles.split('\n').each { file ->
            def name = file.trim()
            if (name) {
              echo "Staging WFL: ${name}"
              sh "cp ${name} artifacts/"
            }
          }
        }
      }
    }

    // ── Stage 4 ────────────────────────────────────────────────────
    stage('Wait for PR merge to main') {
      when {
        expression { env.BRANCH_NAME != 'main' }
      }
      steps {
        script {
          def branch = env.BRANCH_NAME
          echo "Looking for open PR for branch: ${branch}"

          def prListJson = sh(
            script: """
              curl -s \
                -H "Authorization: token ${GITHUB_TOKEN}" \
                -H "Accept: application/vnd.github.v3+json" \
                "https://api.github.com/repos/sabah-unisys/testrepo/pulls?head=sabah-unisys:${branch}&state=open"
            """,
            returnStdout: true
          ).trim()

          def prs = readJSON text: prListJson

          if (prs.size() == 0) {
            error "No open PR found for branch '${branch}'. " +
                  "Please open a PR to main before this pipeline can deploy."
          }

          def prNumber = prs[0].number
          def prTitle  = prs[0].title
          echo "Found PR #${prNumber}: '${prTitle}'. Waiting for merge..."

          timeout(time: 48, unit: 'HOURS') {
            waitUntil(initialRecurrencePeriod: 60000) {   // checks every 60 seconds
              def prJson = sh(
                script: """
                  curl -s \
                    -H "Authorization: token ${GITHUB_TOKEN}" \
                    -H "Accept: application/vnd.github.v3+json" \
                    "https://api.github.com/repos/sabah-unisys/testrepo/pulls/${prNumber}"
                """,
                returnStdout: true
              ).trim()

              def pr = readJSON text: prJson
              def merged = (pr.state == 'closed' && pr.merged == true)
              if (!merged) echo "PR #${prNumber} not merged yet. Checking again in 60s..."
              return merged
            }
          }

          echo "PR #${prNumber} merged into main. Proceeding to deploy."
        }
      }
    }

    // ── Stage 5 ────────────────────────────────────────────────────
    stage('Transfer to Unisys') {
      steps {
        script {
          ['cobol_files.txt', 'wfl_files.txt'].each { txtFile ->
            def path = "${CHANGED_FILES_DIR}/${txtFile}"
            if (fileExists(path) && readFile(path).trim()) {
              readFile(path).trim().split('\n').each { file ->
                def name = file.trim()
                if (name) {
                  echo "Transferring: ${name}"
                  sh """
                    ftp -n ${UNISYS_HOST} <<EOF
                    user ${UNISYS_USER} ${UNISYS_PASS}
                    binary
                    cd USERDATA/PROGRAMS
                    put ${name}
                    bye
                    EOF
                  """
                }
              }
            }
          }
        }
      }
    }

    // ── Stage 6 ────────────────────────────────────────────────────
    stage('Compile COBOL on Unisys') {
      when {
        expression {
          fileExists("${CHANGED_FILES_DIR}/cobol_files.txt") &&
          readFile("${CHANGED_FILES_DIR}/cobol_files.txt").trim()
        }
      }
      steps {
        script {
          def cobolFiles = readFile("${CHANGED_FILES_DIR}/cobol_files.txt").trim()
          cobolFiles.split('\n').each { file ->
            def name = file.trim()
            if (name) {
              echo "Compiling COBOL on Unisys: ${name}"
              sh """
                expect -c '
                  spawn telnet ${UNISYS_HOST}
                  expect "Userid:"
                  send "${UNISYS_USER}\\r"
                  expect "Password:"
                  send "${UNISYS_PASS}\\r"
                  expect "OK"
                  send "COMPILE ${name}/SOURCE\\r"
                  expect "OK"
                  send "BYE\\r"
                '
              """
            }
          }
        }
      }
    }

    // ── Stage 7 ────────────────────────────────────────────────────
    stage('Submit WFL job on Unisys') {
      when {
        expression {
          fileExists("${CHANGED_FILES_DIR}/wfl_files.txt") &&
          readFile("${CHANGED_FILES_DIR}/wfl_files.txt").trim()
        }
      }
      steps {
        script {
          def wflFiles = readFile("${CHANGED_FILES_DIR}/wfl_files.txt").trim()
          wflFiles.split('\n').each { file ->
            def name = file.trim()
            if (name) {
              echo "Submitting WFL job: ${name}"
              sh """
                expect -c '
                  spawn telnet ${UNISYS_HOST}
                  expect "Userid:"
                  send "${UNISYS_USER}\\r"
                  expect "Password:"
                  send "${UNISYS_PASS}\\r"
                  expect "OK"
                  send "START ${name}\\r"
                  expect "OK"
                  send "BYE\\r"
                '
              """
            }
          }
        }
      }
    }

  }

  // ── Post actions ─────────────────────────────────────────────────
  post {
    always {
      script {
        echo "=== Build Summary ==="
        ['cobol_files.txt', 'wfl_files.txt'].each { txtFile ->
          def path = "${CHANGED_FILES_DIR}/${txtFile}"
          if (fileExists(path) && readFile(path).trim()) {
            echo "--- ${txtFile} ---"
            echo readFile(path).trim()
          }
        }
      }
    }
    success {
      echo "Pipeline completed successfully for branch: ${env.BRANCH_NAME}"
    }
    failure {
      echo "Pipeline failed for branch: ${env.BRANCH_NAME}"
    }
  }
}
