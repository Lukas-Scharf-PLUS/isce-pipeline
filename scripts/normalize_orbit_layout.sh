#!/usr/bin/env bash
set -euo pipefail

echo "=== Normalizing Sentinel-1 orbit files for ISCE ==="

# =====================================================
# === INPUT PARAMETERS ================================
# =====================================================

SRC_DIR="${1:?ERROR: SRC_DIR not provided}"
DEST_DIR="${2:?ERROR: DEST_DIR not provided}"

echo "SRC_DIR:  $SRC_DIR"
echo "DEST_DIR: $DEST_DIR"

# =====================================================
# === VALIDATION ======================================
# =====================================================

if [ ! -d "$SRC_DIR" ]; then
  echo "ERROR: SRC_DIR does not exist: $SRC_DIR"
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

  # create/update symlink
  ln -sfn "$(realpath "$f")" "$target"

  count=$((count+1))
done < <(find "$SRC_DIR" -type f \( -iname '*.EOF' \) -print0)

# =====================================================
# === SUMMARY =========================================
# =====================================================

echo "----------------------------------------"
echo "Normalized files: $count"
echo "Skipped files:    $skipped"
echo "Destination:      $DEST_DIR"
echo "----------------------------------------"

echo "=== Layout summary ==="
find "$DEST_DIR" -maxdepth 3 \( -type f -o -type l \) | sort
