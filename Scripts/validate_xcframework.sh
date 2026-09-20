#!/usr/bin/env bash
# Validate (and minimally repair) TensorFlowLiteC.xcframework bundle metadata and exported symbols.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=Scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

XCFRAMEWORK="${1:-${FINAL_XCFRAMEWORK}}"
REPAIR_METADATA="${REPAIR_METADATA:-1}"
MODIFICATIONS_LOG="${CACHE_DIR}/metadata_modifications.log"

REQUIRED_SYMBOLS=(
  TfLiteModelCreate
  TfLiteInterpreterCreate
  TfLiteInterpreterInvoke
)

find_framework_binary() {
  local fw="$1"
  if [[ -f "${fw}/TensorFlowLiteC" ]]; then
    echo "${fw}/TensorFlowLiteC"
    return 0
  fi
  find "${fw}" -maxdepth 1 -type f ! -name 'Info.plist' 2>/dev/null | head -1
}

binary_min_os() {
  local bin="$1"
  local from_vtool=""
  if command -v vtool >/dev/null 2>&1; then
    from_vtool="$(vtool -show-build "${bin}" 2>/dev/null | awk '/minos/ {print $2; exit}' || true)"
  fi
  if [[ -n "${from_vtool}" ]]; then
    echo "${from_vtool}"
    return 0
  fi
  ruby "${SCRIPT_DIR}/macho_min_os.rb" "${bin}" 2>/dev/null || true
}

ensure_framework_info_plist() {
  local fw="$1"
  local slice_id="$2"
  local bin="$3"
  local plist="${fw}/Info.plist"

  local min_os
  min_os="$(binary_min_os "${bin}")"
  [[ -n "${min_os}" ]] || die "Could not determine minimum iOS version for ${bin} (vtool/macho parser)."

  local had_plist=0
  [[ -f "${plist}" ]] && had_plist=1

  local existing_min=""
  if [[ "${had_plist}" -eq 1 ]]; then
    existing_min="$(plutil -extract MinimumOSVersion raw -o - "${plist}" 2>/dev/null || true)"
  fi

  local needs_write=0
  if [[ "${had_plist}" -eq 0 ]]; then
    needs_write=1
  elif [[ -z "${existing_min}" ]]; then
    needs_write=1
  elif [[ "${existing_min}" != "${min_os}" ]]; then
    log "WARNING: ${plist} MinimumOSVersion=${existing_min} differs from binary min OS ${min_os}; updating to match binary."
    needs_write=1
  fi

  for key in CFBundleIdentifier CFBundleName CFBundlePackageType CFBundleShortVersionString CFBundleVersion; do
    if [[ "${had_plist}" -eq 0 ]] || ! plutil -extract "${key}" raw -o - "${plist}" >/dev/null 2>&1; then
      needs_write=1
      break
    fi
  done

  if [[ "${needs_write}" -eq 1 && "${REPAIR_METADATA}" == "1" ]]; then
    mkdir -p "${CACHE_DIR}"
    {
      echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") slice=${slice_id}"
      if [[ "${had_plist}" -eq 0 ]]; then
        echo "  Created missing Info.plist at ${plist}"
      else
        echo "  Updated Info.plist at ${plist}"
      fi
      echo "  MinimumOSVersion set to ${min_os} (from binary via vtool/macho_min_os.rb)"
      echo "  CFBundleShortVersionString / CFBundleVersion set to ${TFLITE_VERSION}"
      echo "  CFBundleIdentifier set to org.tensorflow.TensorFlowLiteC"
    } >> "${MODIFICATIONS_LOG}"

    cat > "${plist}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleIdentifier</key>
  <string>org.tensorflow.TensorFlowLiteC</string>
  <key>CFBundleName</key>
  <string>TensorFlowLiteC</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>${TFLITE_VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${TFLITE_VERSION}</string>
  <key>MinimumOSVersion</key>
  <string>${min_os}</string>
</dict>
</plist>
PLIST
    log "Metadata repair: wrote ${plist} (MinimumOSVersion=${min_os})"
  elif [[ "${needs_write}" -eq 1 ]]; then
    die "Framework metadata incomplete at ${plist}; set REPAIR_METADATA=1 to repair."
  fi

  echo "${min_os}"
}

validate_symbols() {
  local bin="$1"
  local sym_out
  sym_out="$(mktemp)"
  if nm -gU "${bin}" > "${sym_out}" 2>/dev/null || nm "${bin}" > "${sym_out}" 2>/dev/null; then
    if grep -q TfLite "${sym_out}"; then
      log "Exported TfLite symbols (sample from nm):"
      grep TfLite "${sym_out}" | head -20 | while read -r line; do
        log "  ${line}"
      done
    fi
  else
    log "nm unavailable or empty; falling back to validate_symbols.rb"
  fi

  if ruby "${SCRIPT_DIR}/validate_symbols.rb" "${bin}" > "${sym_out}" 2>/dev/null; then
    while read -r line; do
      [[ -n "${line}" ]] && log "  ${line}"
    done < "${sym_out}"
    rm -f "${sym_out}"
    return 0
  fi

  rm -f "${sym_out}"
  die "Required TfLite symbols not found in ${bin}"
}

xcframework_uses_static_libraries() {
  local xc="$1"
  [[ -f "${xc}/ios-arm64/${STATIC_LIB_BASENAME}" ]] || [[ -f "${xc}/ios-arm64_x86_64-simulator/${STATIC_LIB_BASENAME}" ]]
}

validate_library_slice() {
  local slice_dir="$1"
  local slice_id
  slice_id="$(basename "${slice_dir}")"
  local bin="${slice_dir}/${STATIC_LIB_BASENAME}"
  [[ -f "${bin}" ]] || die "Missing ${STATIC_LIB_BASENAME} in slice ${slice_id}"

  log "======== Slice (static library): ${slice_id} ========"
  log "Binary: ${bin}"
  validate_binary_slice "${bin}" "${slice_id}" "${slice_dir}/Headers/${MODULEMAP_NAME}"
  local min_os
  min_os="$(binary_min_os "${bin}")"
  [[ -n "${min_os}" ]] || die "Could not determine minimum iOS for ${bin}"
  log "Slice ${slice_id} minimum iOS (binary): ${min_os}"
  printf '%s\n' "${min_os}"
}

validate_framework_slice() {
  local slice_dir="$1"
  local slice_id
  slice_id="$(basename "${slice_dir}")"
  local fw="${slice_dir}/TensorFlowLiteC.framework"
  [[ -d "${fw}" ]] || die "Missing TensorFlowLiteC.framework in slice ${slice_id}"

  local bin
  bin="$(find_framework_binary "${fw}")"
  [[ -n "${bin}" && -f "${bin}" ]] || die "Missing binary in ${fw}"

  log "======== Slice (framework bundle): ${slice_id} ========"
  log "Binary: ${bin}"
  validate_binary_slice "${bin}" "${slice_id}" "${fw}/Modules/module.modulemap"
  local min_os
  min_os="$(ensure_framework_info_plist "${fw}" "${slice_id}" "${bin}")"
  if [[ -f "${fw}/Info.plist" ]]; then
    log "Info.plist:"
    plutil -p "${fw}/Info.plist" | while read -r line; do log "  ${line}"; done
  fi
  log "Slice ${slice_id} minimum iOS (binary): ${min_os}"
  printf '%s\n' "${min_os}"
}

validate_binary_slice() {
  local bin="$1"
  local slice_id="$2"
  local modulemap="$3"

  log "file:"
  file "${bin}" | while read -r line; do log "  ${line}"; done

  log "lipo -info:"
  if lipo -info "${bin}" 2>/dev/null | while read -r line; do log "  ${line}"; done; then
    :
  else
    log "  (lipo unavailable; using file(1) output above)"
  fi

  log "vtool -show-build:"
  if vtool -show-build "${bin}" 2>/dev/null | while read -r line; do log "  ${line}"; done; then
    :
  else
    log "  (vtool unavailable; using macho_min_os.rb for deployment target)"
  fi

  if [[ -f "${modulemap}" ]]; then
    if ! grep -qE '(^framework module|^module) TensorFlowLiteC' "${modulemap}"; then
      die "Unexpected module name in ${modulemap}"
    fi
    log "OK module.modulemap declares module TensorFlowLiteC"
  else
    die "Missing module.modulemap at ${modulemap}"
  fi

  validate_symbols "${bin}"
}

validate_slice() {
  local slice_dir="$1"
  if [[ -f "${slice_dir}/${STATIC_LIB_BASENAME}" ]]; then
    validate_library_slice "${slice_dir}"
  else
    validate_framework_slice "${slice_dir}"
  fi
}

main() {
  [[ -d "${XCFRAMEWORK}" ]] || die "XCFramework not found: ${XCFRAMEWORK}"

  require_cmd file
  require_cmd plutil

  log "Validating ${XCFRAMEWORK} (TensorFlowLiteC ${TFLITE_VERSION})"

  if [[ -f "${XCFRAMEWORK}/Info.plist" ]]; then
    log "XCFramework Info.plist:"
    plutil -p "${XCFRAMEWORK}/Info.plist" | while read -r line; do log "  ${line}"; done
  fi

  local slices
  slices="$(find "${XCFRAMEWORK}" -mindepth 1 -maxdepth 1 -type d ! -name '.*' | sort)"
  [[ -n "${slices}" ]] || die "No platform slices found in ${XCFRAMEWORK}"

  local global_min=""
  while read -r slice_dir; do
    [[ -n "${slice_dir}" ]] || continue
    local slice_min
    slice_min="$(validate_slice "${slice_dir}")"
    if [[ -z "${global_min}" ]]; then
      global_min="${slice_min}"
    else
      # Keep highest min OS across slices for Package.swift platform recommendation.
      global_min="$(ruby -e '
a=ARGV[0].split(".").map(&:to_i)
b=ARGV[1].split(".").map(&:to_i)
n=[a.size,b.size].max
a.concat([0]*(n-a.size))
b.concat([0]*(n-b.size))
puts a.zip(b).map{|x,y| [x,y].max}.join(".")
' "${global_min}" "${slice_min}")"
    fi
  done <<< "${slices}"

  log "Recommended SwiftPM platform (.iOS): ${global_min}"
  mkdir -p "${ARTIFACTS_DIR}"
  echo "${global_min}" > "${ARTIFACTS_DIR}/detected_minimum_ios.txt"
  log "Validation succeeded."
}

main "$@"
