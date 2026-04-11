#!/bin/bash
set -euo pipefail

# ============================================================
#  Local orchestration script
#  Finds the latest successful build_iso.yml run, extracts the
#  SHA256 checksum for bazzite-deck-stable-amd64.iso from the
#  job logs, downloads the ISO, and verifies the checksum.
#
#  Dependencies: gh (GitHub CLI), jq, curl, sha256sum
# ============================================================

OWNER="AeroCore-IO"
REPO="bazzite"
ISO_NAME="bazzite-deck-stable-amd64.iso"
DOWNLOAD_URL="https://downloads.aerocore.io/${ISO_NAME}"
DOWNLOAD_DIR="${DOWNLOAD_DIR:-.}"

# ============================================================
#  Output helpers
# ============================================================
info() { echo "[INFO]  $*"; }
ok()   { echo "[OK]    $*"; }
err()  { echo "[ERROR] $*" >&2; }

# ============================================================
#  Preflight checks
# ============================================================
for cmd in gh jq curl sha256sum; do
    if ! command -v "$cmd" &>/dev/null; then
        err "Missing dependency: $cmd, please install it first"
        exit 1
    fi
done

if ! gh auth status &>/dev/null; then
    err "GitHub CLI is not authenticated. Please run: gh auth login"
    exit 1
fi

# ============================================================
#  Step 1: Find the latest successful build_iso.yml run
# ============================================================
info "[1/3] Finding latest successful build_iso.yml run..."

RUN_ID=$(gh api \
    "repos/${OWNER}/${REPO}/actions/workflows/build_iso.yml/runs?status=success&per_page=1" \
    --jq '.workflow_runs[0].id')

if [ -z "$RUN_ID" ] || [ "$RUN_ID" = "null" ]; then
    err "No successful build_iso.yml run found"
    exit 1
fi

ok "Found run #${RUN_ID}: https://github.com/${OWNER}/${REPO}/actions/runs/${RUN_ID}"

# ============================================================
#  Step 2: Extract checksum from the bazzite-deck job logs
#
#  The build_iso.yml matrix produces job names like:
#    build-iso (bazzite-deck, 43)       <-- we want this
#    build-iso (bazzite-deck-gnome, 43) <-- skip
#    build-iso (bazzite, 43)            <-- skip
#
#  The "Display ISO Checksum" step writes to GITHUB_STEP_SUMMARY
#  (not visible in gh run view output) AND also runs:
#    cat <path>/<iso_name>-CHECKSUM
#  which prints to stdout and IS captured in the job logs.
#  Output format:  <sha256hash>  bazzite-deck-stable-amd64.iso
# ============================================================
info "[2/3] Extracting checksum from job logs..."

# "bazzite-deck," (with comma) matches bazzite-deck but NOT bazzite-deck-gnome
JOB_ID=$(gh api \
    "repos/${OWNER}/${REPO}/actions/runs/${RUN_ID}/jobs?per_page=100" \
    --jq '[.jobs[] | select(.name | test("^build-iso \\(bazzite-deck,"))] | .[0].id')

if [ -z "$JOB_ID" ] || [ "$JOB_ID" = "null" ]; then
    err "Could not find build-iso (bazzite-deck, ...) job in run #${RUN_ID}"
    exit 1
fi

info "Found job #${JOB_ID}"

# gh api follows the 302 redirect and returns the plain-text log
SUMMARY_HASH=$(gh api \
    "repos/${OWNER}/${REPO}/actions/jobs/${JOB_ID}/logs" \
    2>/dev/null \
    | grep -oP '[a-f0-9]{64}(?=\s+'"${ISO_NAME}"')' \
    | head -1 || true)

if [ -z "$SUMMARY_HASH" ]; then
    err "Could not extract SHA256 checksum for ${ISO_NAME} from job logs"
    exit 1
fi

ok "Expected checksum: ${SUMMARY_HASH}"

# ============================================================
#  Step 3: Download ISO and verify checksum
# ============================================================
info "[3/3] Downloading ${ISO_NAME} from ${DOWNLOAD_URL}..."

mkdir -p "${DOWNLOAD_DIR}"
DEST="${DOWNLOAD_DIR}/${ISO_NAME}"

curl -L --progress-bar -o "${DEST}" "${DOWNLOAD_URL}"

info "Verifying checksum..."
ACTUAL_HASH=$(sha256sum "${DEST}" | awk '{print $1}')

if [ "${ACTUAL_HASH}" = "${SUMMARY_HASH}" ]; then
    ok "Checksum verified: ${ACTUAL_HASH}"
    ok "Done. File saved to: $(realpath "${DEST}")"
else
    err "Checksum mismatch!"
    err "Expected: ${SUMMARY_HASH}"
    err "Actual:   ${ACTUAL_HASH}"
    rm -f "${DEST}"
    exit 1
fi
