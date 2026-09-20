#!/usr/bin/env bash
# Download, extract, reuse or assemble TensorFlowLiteC.xcframework, validate, and install under Artifacts/.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

STAGING_DIR="${CACHE_DIR}/staging"
WORK_XCFRAMEWORK="${STAGING_DIR}/${XCFRAMEWORK_NAME}"

find_framework_binary() {
  local fw="$1"
  local candidate="${fw}/TensorFlowLiteC"
  [[ -f "${candidate}" ]] && echo "${candidate}" && return 0
  candidate="$(find "${fw}" -maxdepth 1 -type f -perm +111 2>/dev/null | head -1)"
  [[ -n "${candidate}" ]] && echo "${candidate}" && return 0
  return 1
}

locate_xcframework_in_pod() {
  local pod_root="$1"
  local xc="${pod_root}/Frameworks/${XCFRAMEWORK_NAME}"
  if [[ -d "${xc}" ]]; then
    echo "${xc}"
    return 0
  fi
  find "${pod_root}" -type d -name "${XCFRAMEWORK_NAME}" 2>/dev/null | head -1
}

locate_standalone_frameworks() {
  local pod_root="$1"
  find "${pod_root}" -type d -name 'TensorFlowLiteC.framework' 2>/dev/null
}

print_discovered_files() {
  local pod_root="$1"
  log "Files discovered under pod root (${pod_root}):"
  find "${pod_root}" \( -name 'TensorFlowLiteC.framework' -o -name "${XCFRAMEWORK_NAME}" -o -name 'module.modulemap' \) 2>/dev/null \
    | sort \
    | while read -r path; do
        log "  ${path}"
      done
}

FRAMEWORK_XCFRAMEWORK="${STAGING_DIR}/TensorFlowLiteC.framework-style.xcframework"

# Official CocoaPods artifact is a *static* Mach-O inside TensorFlowLiteC.framework folders.
# That layout makes Xcode/SPM copy TensorFlowLiteC.framework into the app bundle (App Store rejection).
# Re-pack as a static-library XCFramework (libTensorFlowLiteC.a + Headers) for correct link-only behavior.
convert_framework_xcframework_to_static_library() {
  local src_xc="$1"
  local out_xc="$2"
  require_cmd xcodebuild

  local prep="${STAGING_DIR}/static-lib-prep"
  rm -rf "${prep}"
  mkdir -p "${prep}"

  local -a xcbf_args=()
  local slice_dir slice_id fw headers_dir lib_path
  while read -r slice_dir; do
    [[ -n "${slice_dir}" ]] || continue
    slice_id="$(basename "${slice_dir}")"
    fw="${slice_dir}/TensorFlowLiteC.framework"
    [[ -d "${fw}" ]] || die "Expected TensorFlowLiteC.framework in slice ${slice_id}"

    local bin="${fw}/TensorFlowLiteC"
    [[ -f "${bin}" ]] || die "Missing static binary ${bin}"

    local slice_prep="${prep}/${slice_id}"
    mkdir -p "${slice_prep}/Headers"
    cp "${bin}" "${slice_prep}/${STATIC_LIB_BASENAME}"
    ditto "${fw}/Headers" "${slice_prep}/Headers"
    if [[ -f "${fw}/Modules/${MODULEMAP_NAME}" ]]; then
      cp "${fw}/Modules/${MODULEMAP_NAME}" "${slice_prep}/Headers/${MODULEMAP_NAME}"
      # Static-library XCFrameworks: plain "module" (not "framework module") for reliable Archive builds.
      sed -i '' 's/framework module/module/' "${slice_prep}/Headers/${MODULEMAP_NAME}" 2>/dev/null \
        || sed -i 's/framework module/module/' "${slice_prep}/Headers/${MODULEMAP_NAME}"
    fi

    log "Static library slice prep ${slice_id}:"
    log "  lib: ${slice_prep}/${STATIC_LIB_BASENAME} (from ${bin})"
    log "  headers: ${slice_prep}/Headers"

    xcbf_args+=(-library "${slice_prep}/${STATIC_LIB_BASENAME}" -headers "${slice_prep}/Headers")
  done < <(find "${src_xc}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)

  [[ ${#xcbf_args[@]} -gt 0 ]] || die "No slices found to convert in ${src_xc}"
  rm -rf "${out_xc}"
  log "Creating static-library ${XCFRAMEWORK_NAME} (link-only, no framework bundle embed) ..."
  xcodebuild -create-xcframework "${xcbf_args[@]}" -output "${out_xc}"
}

copy_or_build_xcframework() {
  local pod_root="$1"
  rm -rf "${STAGING_DIR}"
  mkdir -p "${STAGING_DIR}"

  local existing_xc
  existing_xc="$(locate_xcframework_in_pod "${pod_root}")"
  if [[ -n "${existing_xc}" && -d "${existing_xc}" ]]; then
    log "Reusing existing XCFramework from official pod (framework layout):"
    log "  Source: ${existing_xc}"
    ditto "${existing_xc}" "${FRAMEWORK_XCFRAMEWORK}"
    convert_framework_xcframework_to_static_library "${FRAMEWORK_XCFRAMEWORK}" "${WORK_XCFRAMEWORK}"
    return 0
  fi

  log "No ${XCFRAMEWORK_NAME} found; searching for separate TensorFlowLiteC.framework slices ..."
  local frameworks
  frameworks="$(locate_standalone_frameworks "${pod_root}")"
  [[ -n "${frameworks}" ]] || die "No TensorFlowLiteC.xcframework or TensorFlowLiteC.framework found in downloaded pod."

  require_cmd xcodebuild
  local -a xcbf_args=()
  while read -r fw; do
    [[ -n "${fw}" ]] || continue
    log "  Framework for xcodebuild -create-xcframework: ${fw}"
    xcbf_args+=(-framework "${fw}")
  done <<< "${frameworks}"

  log "Creating ${XCFRAMEWORK_NAME} with xcodebuild -create-xcframework (framework layout) ..."
  xcodebuild -create-xcframework "${xcbf_args[@]}" -output "${FRAMEWORK_XCFRAMEWORK}"
  convert_framework_xcframework_to_static_library "${FRAMEWORK_XCFRAMEWORK}" "${WORK_XCFRAMEWORK}"
}

install_artifact() {
  mkdir -p "${ARTIFACTS_DIR}"
  rm -rf "${FINAL_XCFRAMEWORK}"
  ditto "${WORK_XCFRAMEWORK}" "${FINAL_XCFRAMEWORK}"
  log "Installed: ${FINAL_XCFRAMEWORK}"
}

write_provenance() {
  local pod_root="$1"
  local zip_path="${ARTIFACTS_DIR}/${XCFRAMEWORK_NAME}.zip"
  rm -f "${zip_path}"
  (
    cd "${ARTIFACTS_DIR}"
    zip -rq "${XCFRAMEWORK_NAME}.zip" "${XCFRAMEWORK_NAME}"
  )
  local zip_checksum
  zip_checksum="$(sha256_file "${zip_path}")"

  {
    if [[ -f "${DOWNLOAD_DIR}/provenance.partial.txt" ]]; then
      cat "${DOWNLOAD_DIR}/provenance.partial.txt"
    fi
    echo "Pod extract root: ${pod_root}"
    echo "XCFramework path: ${FINAL_XCFRAMEWORK}"
    echo "XCFramework zip: ${zip_path}"
    echo "XCFramework zip SHA-256: ${zip_checksum}"
    echo "Packaged at (UTC): $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo ""
    echo "SwiftPM remote checksum (swift package compute-checksum):"
    echo "  ${zip_checksum}"
  } > "${PROVENANCE_FILE}"
  log "Wrote ${PROVENANCE_FILE}"
}

main() {
  require_cmd curl
  require_cmd ditto

  log "Cleaning previous staging and artifact ..."
  rm -rf "${STAGING_DIR}" "${FINAL_XCFRAMEWORK}"

  "${SCRIPT_DIR}/download_tflite.sh" >/dev/null
  local pod_root
  pod_root="$(cat "${DOWNLOAD_DIR}/pod_root.path")"

  print_discovered_files "${pod_root}"
  copy_or_build_xcframework "${pod_root}"

  log "Validating XCFramework ..."
  "${SCRIPT_DIR}/validate_xcframework.sh" "${WORK_XCFRAMEWORK}"

  install_artifact
  write_provenance "${pod_root}"

  if [[ -f "${MODIFICATIONS_LOG}" ]]; then
    cp "${MODIFICATIONS_LOG}" "${ARTIFACTS_DIR}/METADATA_MODIFICATIONS.log"
    log "Wrote ${ARTIFACTS_DIR}/METADATA_MODIFICATIONS.log"
  fi

  log "Done. Add this package to Xcode via File → Add Package Dependencies → Add Local ..."
}

main "$@"
