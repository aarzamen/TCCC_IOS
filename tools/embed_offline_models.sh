#!/bin/bash
# Xcode pre-build script: model staging is explicit and separate from compilation.
set -euo pipefail
if [[ -z "${TCCC_OFFLINE_MODELS_DIR:-}" ]]; then
  if [[ "${TCCC_REQUIRE_OFFLINE_MODELS:-NO}" == "YES" ]]; then
    echo 'error: TCCC_OFFLINE_MODELS_DIR is required for this offline release build.' >&2
    exit 1
  fi
  echo 'Offline model embedding skipped (developer build; installed assets still resolve).'
  exit 0
fi
: "${TARGET_BUILD_DIR:?Xcode build directory required}"
: "${UNLOCALIZED_RESOURCES_FOLDER_PATH:?Xcode resource path required}"
: "${SRCROOT:?Xcode source root required}"
python_bin="${TCCC_STAGING_PYTHON:-/usr/bin/python3}"
"$python_bin" "$SRCROOT/tools/stage_offline_models.py" --output "$TCCC_OFFLINE_MODELS_DIR" --verify
resource_parent="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
mkdir -p "$resource_parent"
# ditto follows symlinks in staged resources; source manifests are already verified.
/usr/bin/ditto "$TCCC_OFFLINE_MODELS_DIR" "$resource_parent/OfflineModels"
"$python_bin" "$SRCROOT/tools/stage_offline_models.py" --output "$resource_parent/OfflineModels" --verify
