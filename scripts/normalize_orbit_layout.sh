#!/usr/bin/env bash
set -euo pipefail

echo "=== Normalizing Sentinel-1 orbit files for ISCE ==="

# =====================================================
# === INPUT PARAMETERS ================================
# =====================================================

SRC_DIR="${1:?ERROR: SRC_DIR not provided}"
DEST_DIR="${2:?ERROR: DEST_DIR not provided}"
DELETE_SRC="${3:-false}"   # optional: true/false

echo "SRC_DIR:     $SRC_DIR"
echo "DEST_DIR:    $DEST_DIR"
echo "DELETE_SRC:  $DELETE_SRC"

# =====================================================
# === VALIDATION ======================================
# =====================================================

if [ ! -d "$SRC_DIR" ]; then
  echo "ERROR: SRC_DIR does not exist: $SRC_DIR"
  exit 1
fi

# Prevent dangerous cases
if [[ "$SRC_DIR" == "/" || "$DEST_DIR" == "/" ]]; then
  echo "ERROR: refusing to operate on root directory"
  exit 1
fi

# =====================================================
# === PREPARE DESTINATION STRUCTURE ====================
# =====================================================

mkdir -p \
  "${DEST_DIR}/S1A/precise" "${DEST_DIR}/S1A/restituted" \
  "${DEST_DIR}/S1B/precise" "${DEST_DIR}/S1B/restituted" \
  "${DEST_DIR}/S1C/precise" "${DEST_DIR}/S1C/restituted"

# =====================================================
# === NORMALIZE FILES =================================
# =====================================================

count=0
skipped=0
copied=0

while IFS= read -r -d '' f; do
  bn="$(basename "$f")"

  sat=""
  typ=""

  # --- detect satellite ---
  [[ "$bn" == S1A_* ]] && sat="S1A"
  [[ "$bn" == S1B_* ]] && sat="S1B"
  [[ "$bn" == S1C_* ]] && sat="S1C"

  # --- detect orbit type ---
  [[ "$bn" == *AUX_POEORB* ]] && typ="precise"
  [[ "$bn" == *AUX_RESORB* ]] && typ="restituted"

  if [[ -z "$sat" || -z "$typ" ]]; then
    skipped=$((skipped+1))
    continue
  fi

  target="${DEST_DIR}/${sat}/${typ}/${bn}"

  # avoid unnecessary copy if file already exists
  if [ -f "$target" ]; then
    continue
  fi

  cp "$f" "$target"
  copied=$((copied+1))
  count=$((count+1))

done < <(find "$SRC_DIR" -type f \( -iname '*.EOF' \) -print0)

# =====================================================
# === VALIDATION CHECK ================================
# =====================================================

if [ "$count" -eq 0 ]; then
  echo "ERROR: No orbit files processed!"
  exit 1
fi

# =====================================================
# === OPTIONAL CLEANUP ================================
# =====================================================

if [ "$DELETE_SRC" == "true" ]; then
  echo "Deleting source directory: $SRC_DIR"
  rm -rf "$SRC_DIR"
fi

# =====================================================
# === SUMMARY =========================================
# =====================================================

echo "----------------------------------------"
echo "Total processed: $count"
echo "Copied files:    $copied"
echo "Skipped files:   $skipped"
echo "Destination:     $DEST_DIR"
echo "----------------------------------------"

echo "=== Layout summary ==="
find "$DEST_DIR" -maxdepth 3 -type f | sort