// ==============================================================================
// Jenkins Multibranch Pipeline for Unisys MCP files (Musk-Melon repo)
//
// Trigger model : Pull-request only, via periodic repo scan (no webhook needed).
//                 Configure this in the Multibranch job, NOT here:
//                   - Branch Sources > GitHub > Behaviours:
//                         "Discover pull requests from origin"
//                         (optionally also "from forks")
//                         remove "Discover branches" if you want PR-only jobs
//                   - Scan Repository Triggers >
//                         [x] Periodically if not otherwise run  ->  e.g. 2 min
//                     (this periodic scan is what polls GitHub for new PRs)
//
// What it does  : 1. Lists the changed MCP files and saves the list to a text file
//                 2. For each changed MCP file:
//                       - NEW file      -> prints the entire content
//                       - MODIFIED file -> prints only the line changes (diff)
//                 Everything is printed to the build log (visible in the UI) and
//                 also archived as build artifacts.
//
// Deployment    : add a 'Deploy' stage later (placeholder is at the bottom).
// ==============================================================================

pipeline {
    agent any

    options {
        buildDiscarder(logRotator(numToKeepStr: '20'))
        timestamps()
    }

    environment {
        // Fallback target branch if Jenkins doesn't provide CHANGE_TARGET.
        DEFAULT_TARGET = 'master'
        // Space-separated MCP extensions to track. Matching is case-insensitive,
        // so listing the lowercase form also covers .C74_M, .DAS_M, etc.
        MCP_EXTENSIONS = 'c74_m c85_m das_m dat_m'
    }

    stages {

        stage('Not a PR - skip') {
            when { not { changeRequest() } }
            steps {
                echo 'This build is not a pull request. The pipeline only runs for PRs, so nothing to do.'
            }
        }

        stage('Checkout') {
            when { changeRequest() }
            steps {
                // Populates the workspace with the PR revision and configures the
                // 'origin' remote (with the job's GitHub credentials) for the
                // git commands in the following stages.
                checkout scm
            }
        }

        stage('Changed MCP files') {
            when { changeRequest() }
            steps {
                sh '''#!/usr/bin/env bash
set -euo pipefail

TARGET="${CHANGE_TARGET:-$DEFAULT_TARGET}"

# Make sure the target branch is available locally to diff against.
git fetch --no-tags origin "+refs/heads/${TARGET}:refs/remotes/origin/${TARGET}"

# Build a regex like: \\.(c74_m|c85_m|das_m|dat_m)$  from MCP_EXTENSIONS
PATTERN="\\.($(echo "${MCP_EXTENSIONS}" | tr ' ' '|'))$"

echo "=================================================================="
echo " PR #${CHANGE_ID}: ${CHANGE_BRANCH} -> ${TARGET}"
echo " ${CHANGE_TITLE:-}"
echo "=================================================================="

# Three-dot diff = changes the PR introduces relative to the merge base.
# Keep only the MCP extensions, save the names to a text file.
git diff --name-only "origin/${TARGET}...HEAD" \
    | grep -iE "${PATTERN}" \
    | sort -u > changed_files.txt || true

echo ""
echo "Changed MCP files:"
echo "------------------"
if [ -s changed_files.txt ]; then
    cat changed_files.txt
else
    echo "(none)"
fi
'''
            }
        }

        stage('Per-file changes') {
            when { changeRequest() }
            steps {
                sh '''#!/usr/bin/env bash
set -euo pipefail

TARGET="${CHANGE_TARGET:-$DEFAULT_TARGET}"
BASE="origin/${TARGET}"
REPORT="pr_${CHANGE_ID}_changes.txt"
: > "$REPORT"

if [ ! -s changed_files.txt ]; then
    echo "No MCP files changed in this pull request." | tee -a "$REPORT"
    exit 0
fi

# Walk every changed entry with its status (A=added, M=modified, D=deleted, R=renamed).
git diff --name-status "${BASE}...HEAD" | while IFS=$'\\t' read -r STATUS PATH_A PATH_B; do

    # The path we report is the new path (PATH_B for renames, otherwise PATH_A).
    FILE="${PATH_B:-$PATH_A}"

    # Only the MCP files captured in the previous stage.
    grep -qxF "$FILE" changed_files.txt || continue

    {
        echo ""
        echo "##################################################################"
        echo "#  [${STATUS}]  ${FILE}"
        echo "##################################################################"
    } | tee -a "$REPORT"

    case "$STATUS" in
        A*)
            echo ">>> NEW FILE - full content:" | tee -a "$REPORT"
            echo "------------------------------------------------------------------" | tee -a "$REPORT"
            git show "HEAD:${FILE}" | tee -a "$REPORT" || echo "(could not read content)" | tee -a "$REPORT"
            ;;
        D*)
            echo ">>> FILE DELETED" | tee -a "$REPORT"
            ;;
        *)
            echo ">>> MODIFIED - line changes:" | tee -a "$REPORT"
            echo "------------------------------------------------------------------" | tee -a "$REPORT"
            git diff "${BASE}...HEAD" -- "$FILE" | tee -a "$REPORT"
            ;;
    esac
done
'''
            }
        }

        // ----------------------------------------------------------------------
        // Deployment will go here later, e.g.:
        // stage('Deploy') {
        //     when { changeRequest() }
        //     steps {
        //         echo 'Deploy MCP files to target environment...'
        //     }
        // }
        // ----------------------------------------------------------------------
    }

    post {
        always {
            script {
                if (env.CHANGE_ID) {
                    archiveArtifacts artifacts: 'changed_files.txt, pr_*_changes.txt',
                                     allowEmptyArchive: true,
                                     fingerprint: true
                }
            }
        }
    }
}
