#!/usr/bin/env bash
# Shared helpers for TensorFlowLiteC-SPM packaging scripts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=Scripts/version.env
source "${SCRIPT_DIR}/version.env"

CACHE_DIR="${REPO_ROOT}/Scripts/.cache"
DOWNLOAD_DIR="${CACHE_DIR}/download"
EXTRACT_DIR="${CACHE_DIR}/extract"
ARTIFACTS_DIR="${REPO_ROOT}/Artifacts"
XCFRAMEWORK_NAME="TensorFlowLiteC.xcframework"
FINAL_XCFRAMEWORK="${ARTIFACTS_DIR}/${XCFRAMEWORK_NAME}"
PROVENANCE_FILE="${ARTIFACTS_DIR}/PROVENANCE.txt"

log() {
  printf '[TensorFlowLiteC-SPM] %s\n' "$*" >&2
}

die() {
  printf '[TensorFlowLiteC-SPM] ERROR: %s\n' "$*" >&2
  exit 1
}

require_cmd() {
  local cmd="$1"
  command -v "${cmd}" >/dev/null 2>&1 || die "Required command not found: ${cmd}"
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "${path}" | awk '{print $1}'
  else
    sha256sum "${path}" | awk '{print $1}'
  fi
}

# Parse the official CocoaPods podspec JSON and print the source HTTP URL (dl.google.com tarball).
resolve_tflite_download_url() {
  require_cmd curl
  require_cmd jq

  local podspec_file="${CACHE_DIR}/TensorFlowLiteC.podspec.json"
  mkdir -p "${CACHE_DIR}"
  curl -fsSL "${TFLITE_PODSPEC_URL}" -o "${podspec_file}" || die "Failed to download podspec: ${TFLITE_PODSPEC_URL}"

  local spec_version url
  spec_version="$(jq -r '.version // empty' "${podspec_file}")"
  url="$(jq -r '.source.http // empty' "${podspec_file}")"

  [[ "${spec_version}" == "${TFLITE_VERSION}" ]] || die "Podspec version mismatch: expected ${TFLITE_VERSION}, got ${spec_version}"
  [[ -n "${url}" ]] || die "Podspec has no source.http URL"
  echo "${url}"
}
