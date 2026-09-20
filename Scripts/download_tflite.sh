#!/usr/bin/env bash
# Download official TensorFlowLiteC from the CocoaPods distribution (Google-hosted tarball).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

USE_POD_DOWNLOAD="${USE_POD_DOWNLOAD:-0}"
POD_ROOT_FILE="${DOWNLOAD_DIR}/pod_root.path"

download_via_pod() {
  require_cmd pod
  local pod_dir="${DOWNLOAD_DIR}/pod"
  rm -rf "${pod_dir}"
  mkdir -p "${pod_dir}"
  log "Attempting CocoaPods download (packaging only): TensorFlowLiteC ${TFLITE_VERSION}"
  (
    cd "${pod_dir}"
    pod download TensorFlowLiteC --version="${TFLITE_VERSION}" --verbose
  )
  local extracted
  extracted="$(find "${pod_dir}" -type d -name "TensorFlowLiteC-${TFLITE_VERSION}" 2>/dev/null | head -1)"
  if [[ -z "${extracted}" ]]; then
    extracted="$(find "${pod_dir}" -type d -path '*/TensorFlowLiteC/*' -name Frameworks 2>/dev/null | head -1 | xargs dirname 2>/dev/null || true)"
  fi
  if [[ -n "${extracted}" && -d "${extracted}/Frameworks" ]]; then
    echo "${extracted}"
    return 0
  fi
  return 1
}

download_via_podspec_url() {
  local url tarball tarball_name
  url="$(resolve_tflite_download_url)"
  log "Resolved official download URL from CocoaPods podspec:"
  log "  ${url}"

  tarball_name="TensorFlowLiteC-${TFLITE_VERSION}.tar.gz"
  mkdir -p "${DOWNLOAD_DIR}"
  tarball="${DOWNLOAD_DIR}/${tarball_name}"

  log "Downloading ${tarball_name} ..."
  curl -fsSL "${url}" -o "${tarball}" || die "Could not download TensorFlowLiteC ${TFLITE_VERSION} from ${url}"

  local checksum
  checksum="$(sha256_file "${tarball}")"
  log "Download SHA-256: ${checksum}"
  echo "${checksum}" > "${DOWNLOAD_DIR}/${tarball_name}.sha256"

  rm -rf "${EXTRACT_DIR}"
  mkdir -p "${EXTRACT_DIR}"
  log "Extracting archive to ${EXTRACT_DIR} ..."
  tar -xzf "${tarball}" -C "${EXTRACT_DIR}"

  local root="${EXTRACT_DIR}/TensorFlowLiteC-${TFLITE_VERSION}"
  [[ -d "${root}" ]] || die "Expected top-level directory TensorFlowLiteC-${TFLITE_VERSION} in archive"

  {
    echo "TensorFlowLiteC version: ${TFLITE_VERSION}"
    echo "Podspec URL: ${TFLITE_PODSPEC_URL}"
    echo "Source tarball URL: ${url}"
    echo "Source tarball SHA-256: ${checksum}"
    echo "Downloaded at (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  } > "${DOWNLOAD_DIR}/provenance.partial.txt"

  echo "${root}"
}

main() {
  mkdir -p "${DOWNLOAD_DIR}" "${EXTRACT_DIR}"
  local pod_root=""

  if [[ "${USE_POD_DOWNLOAD}" == "1" ]]; then
    if pod_root="$(download_via_pod)"; then
      log "CocoaPods download succeeded: ${pod_root}"
    else
      log "CocoaPods download failed or layout unexpected; falling back to podspec URL download."
      pod_root="$(download_via_podspec_url)"
    fi
  else
    pod_root="$(download_via_podspec_url)"
  fi

  log "Extracted pod root: ${pod_root}"
  printf '%s\n' "${pod_root}" > "${POD_ROOT_FILE}"
  printf '%s\n' "${pod_root}"
}

main "$@"
