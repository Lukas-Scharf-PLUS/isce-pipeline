#!/bin/bash
set -euo pipefail

echo "### VERSION 0.1.2 DEBUG ###"
echo "=== stackSentinel entrypoint ==="

# =========================
# === REQUIRED PARAMS =====
# =========================

: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
: "${DATA_DIR:?DATA_DIR is required}"
: "${ORB_DIR:?ORB_DIR is required}"
: "${DEM:?DEM is required}"

# optional but usually needed
: "${AUX_DIR:=${OUTPUT_DIR}/aux}"

# =========================
# === DEFAULTS ============
# =========================
: "${BBOX:=48.17 48.22 16.34 16.37}"
: "${REF_DATE:?REF_DATE is required}"

: "${C:=2}"
: "${Z:=2}"
: "${R:=6}"
: "${F:=0.5}"

: "${NUM_PROC:=3}"
: "${OMP_THREADS:=2}"

: "${DRY_RUN:=false}"
: "${STAGE:=all}"

# =========================
# === THREAD CONTROL ======
# =========================
export OMP_NUM_THREADS="$OMP_THREADS"
export OPENBLAS_NUM_THREADS="$OMP_THREADS"
export MKL_NUM_THREADS="$OMP_THREADS"


# =========================
# === DEBUG INPUT =========
# =========================

echo "========== DEBUG INPUT =========="
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "DATA_DIR=$DATA_DIR"
echo "ORB_DIR=$ORB_DIR"
echo "DEM=$DEM"
echo "AUX_DIR=$AUX_DIR"
echo "================================="

if [ ! -d "$DATA_DIR" ]; then
    echo "❌ ERROR: DATA_DIR does not exist!"
    exit 1
fi

#echo "=== CONTENT OF DATA_DIR ==="
#ls -al "$DATA_DIR" || true

#echo "=== RECURSIVE STRUCTURE ==="
#ls -R "$DATA_DIR" || true

# detect SAFE files robustly
shopt -s nullglob
SAFE_FILES=("$DATA_DIR"/*.SAFE)

echo "=== SAFE FILE DETECTION ==="
echo "Found ${#SAFE_FILES[@]} SAFE files in $DATA_DIR"

if [[ ${#SAFE_FILES[@]} -eq 0 ]]; then
    echo "⚠️ No SAFE files found directly in DATA_DIR"

    echo "Trying one level deeper..."

    SUBDIRS=("$DATA_DIR"/*/)
    FOUND=0

    for d in "${SUBDIRS[@]}"; do
        inner=("$d"/*.SAFE)
        if [[ ${#inner[@]} -gt 0 ]]; then
            echo "✅ Found SAFE files in subdirectory: $d"
            DATA_DIR="$d"
            SAFE_FILES=("${inner[@]}")
            FOUND=1
            break
        fi
    done

    if [[ $FOUND -eq 0 ]]; then
        echo "❌ ERROR: No SAFE files found anywhere"
        exit 1
    fi
fi

echo "Using DATA_DIR=$DATA_DIR"
echo "SAFE count=${#SAFE_FILES[@]}"


ORIG_DATA_NAME=$(basename "$DATA_DIR")

# =========================
# === RANGE TAG (AUTO) ====
# =========================

echo "=== Detecting date range from SAFE files ==="

# collect SAFE files
mapfile -t SAFE_FILES < <(find "$DATA_DIR" -maxdepth 1 -type d -name "*.SAFE" | sort)

if [[ "${#SAFE_FILES[@]}" -eq 0 ]]; then
    echo "ERROR: No SAFE files found in $DATA_DIR"
    exit 1
fi

DATES=()

for f in "${SAFE_FILES[@]}"; do
    fname=$(basename "$f")

    # extract first YYYYMMDD in filename
    date=$(echo "$fname" | grep -oE '[0-9]{8}' | head -n1 || true)

    if [[ -n "$date" ]]; then
        DATES+=("$date")
    else
        echo "WARNING: could not extract date from $fname"
    fi
done

if [[ "${#DATES[@]}" -eq 0 ]]; then
    echo "ERROR: No valid dates found in SAFE filenames"
    exit 1
fi

# sort and get min/max
IFS=$'\n' SORTED=($(sort <<<"${DATES[*]}"))
unset IFS

MIN_DATE="${SORTED[0]}"
MAX_DATE="${SORTED[-1]}"

RANGE_TAG="${MIN_DATE}_${MAX_DATE}"

echo "Detected date range: $MIN_DATE → $MAX_DATE"
echo "Using RANGE_TAG=$RANGE_TAG"


# =========================
# === WORKDIR ============
# =========================
WORKDIR="${OUTPUT_DIR}/stack_${ORIG_DATA_NAME}_${RANGE_TAG}_c${C}_z${Z}_r${R}_f${F}"

START_TOTAL=$(date +%s)

# safety check
if [[ -z "$WORKDIR" || "$WORKDIR" == "/" || "$WORKDIR" == "$OUTPUT_DIR" ]]; then
    echo "ERROR: WORKDIR is unsafe!"
    exit 1
fi

# set/remove current working directory if it already exists
if [[ "$STAGE" == "stage1" ]]; then
    echo "Stage1: creating fresh WORKDIR"
    rm -rf "$WORKDIR"
    mkdir -p "$WORKDIR"
else
    echo "Reusing existing WORKDIR: $WORKDIR"
fi

# create the working directory where results are saved
mkdir -p "$WORKDIR"
mkdir -p "$WORKDIR/logs"
mkdir -p "$AUX_DIR"


ls "$DATA_DIR"/* | sort > "$WORKDIR/input_scenes.txt"


# =========================
# === PARAMETER LOG =======
# =========================

PARAM_LOG="$WORKDIR/parameters.log"

echo "=== Writing parameter log to $PARAM_LOG ==="

{
    echo "===== STACK SENTINEL PARAMETERS ====="
    echo "RUN_ID=$(date +%Y%m%d_%H%M%S)"
    echo "DATE=$(date)"
    echo ""

    echo "---- PATHS ----"
    echo "OUTPUT_DIR=$OUTPUT_DIR"
    echo "DATA_DIR=$DATA_DIR"
    echo "ORB_DIR=$ORB_DIR"
    echo "DEM=$DEM"
    echo "AUX_DIR=$AUX_DIR"
    echo ""

    echo "---- AOI ----"
    echo "BBOX=$BBOX"
    echo ""

    echo "---- TIME ----"
    echo "REF_DATE=$REF_DATE"
    echo "START_DATE=${START_DATE:-<not set>}"
    echo "END_DATE=${END_DATE:-<not set>}"
    echo "RANGE_TAG=$RANGE_TAG"
    echo ""

    echo "---- INPUT DATA ----"
    echo "INPUT_SCENES_FILE=$WORKDIR/input_scenes.txt"
    echo "NUM_SCENES=$(wc -l < "$WORKDIR/input_scenes.txt")"
    echo ""

    echo "---- PROCESSING PARAMS ----"
    echo "C=$C"
    echo "Z=$Z"
    echo "R=$R"
    echo "F=$F"
    echo ""

    echo "---- PARALLELIZATION ----"
    echo "NUM_PROC=$NUM_PROC"
    echo "OMP_THREADS (user setting)=$OMP_THREADS"
    echo "OMP_NUM_THREADS (effective)=$OMP_NUM_THREADS"
    echo "OPENBLAS_NUM_THREADS=$OPENBLAS_NUM_THREADS"
    echo "MKL_NUM_THREADS=$MKL_NUM_THREADS"
    echo ""

    echo "---- DERIVED ----"
    echo "WORKDIR=$WORKDIR"
    echo "ORIG_DATA_NAME=$ORIG_DATA_NAME"
    echo ""

    echo "---- SYSTEM ----"
    echo "HOSTNAME=$(hostname)"
    echo "USER=$(whoami)"
    echo "PWD=$(pwd)"
    echo "NPROC=$(nproc)"
    echo "KERNEL=$(uname -r)"
    echo ""

    echo "---- MEMORY ----"
    free -h || true
    echo ""

    echo "---- ULIMIT ----"
    ulimit -a || true
    echo ""

    echo "---- CGROUP MEMORY (container limits) ----"
    cat /sys/fs/cgroup/memory.max 2>/dev/null || true
    cat /sys/fs/cgroup/memory.limit_in_bytes 2>/dev/null || true
    echo ""

    echo "---- DISK ----"
    df -h "$OUTPUT_DIR" || true
    echo ""

    echo "---- ENV (filtered) ----"
    env | grep -E '^(OMP|MKL|OPENBLAS|NUM_PROC|OUTPUT_DIR|DATA_DIR|WORKDIR)' || true
    echo ""

    echo "====================================="
} | tee "$PARAM_LOG"



if [[ "$DRY_RUN" == "true" ]]; then
    echo "DRY_RUN enabled → exiting before processing"
    exit 0
fi

# =====================================================
# === RUN stackSentinel.py =============================
# =====================================================

echo "=== Running stackSentinel.py ==="

if [[ "${STAGE:-all}" == "stage1" ]]; then
    echo "=== Running stackSentinel.py (stage1 only) ==="

    START_SS=$(date +%s)

    stackSentinel.py \
      -s "$DATA_DIR" \
      -o "$ORB_DIR" \
      -a "$AUX_DIR" \
      -d "$DEM" \
      -w "$WORKDIR" \
      -b "$BBOX" \
      -m "$REF_DATE" \
      -c "$C" \
      -z "$Z" \
      -r "$R" \
      -f "$F" \
      --num_proc "$NUM_PROC" \
      2>&1 | tee "$WORKDIR/logs/stackSentinel.log"

    END_SS=$(date +%s)
    SS_TIME=$((END_SS - START_SS))

    printf "stackSentinel.py took %02d:%02d (mm:ss)\n" \
        $((SS_TIME/60)) $((SS_TIME%60)) \
        | tee -a "$WORKDIR/timing.log"

else
    echo "=== Skipping stackSentinel.py (STAGE=$STAGE) ==="
fi

# =====================================================
# === RUN ALL STEPS ====================================
# =====================================================

echo "=== Running ISCE steps ==="

if [ ! -d "$WORKDIR/run_files" ]; then
    echo "ERROR: run_files directory missing!"
    exit 1
fi

cd "$WORKDIR/run_files"

# Link DEM once
echo "Linking DEM into $(pwd)"
ln -sf "$DEM" .
[ -f "${DEM}.vrt" ] && ln -sf "${DEM}.vrt" .
[ -f "${DEM}.xml" ] && ln -sf "${DEM}.xml" .

for runfile in run_*; do
    [ -f "$runfile" ] || continue

    # =========================
    # === EXTRACT RUN NUMBER ==
    # =========================
    run_id=$(echo "$runfile" | sed -E 's/run_([0-9]+).*/\1/')
    run_id=$((10#$run_id))

    # optional debug
    echo "STAGE=$STAGE → running run_id=$run_id"

    # =========================
    # === STAGE FILTER ========
    # =========================
    case "${STAGE:-all}" in
    stage1)
        (( run_id < 11 )) || continue
        ;;
    stage2)
        (( run_id >= 11 && run_id < 16 )) || continue
        ;;
    stage3)
        (( run_id == 16 )) || continue
        ;;
    all)
        ;;
    *)
        echo "ERROR: unknown STAGE=$STAGE"
        exit 1
        ;;
    esac

    # =========================
    # === ORIGINAL LOGIC ======
    # =========================
    echo ">>> Running $runfile"

    START_STEP=$(date +%s)

    OMP_NUM_THREADS="$OMP_THREADS" \
    OPENBLAS_NUM_THREADS="$OMP_THREADS" \
    MKL_NUM_THREADS="$OMP_THREADS" \
    bash "$runfile" 2>&1 | tee "$WORKDIR/logs/${runfile}.log"

    END_STEP=$(date +%s)
    DURATION=$((END_STEP - START_STEP))

    printf ">>> %s took %02d:%02d (mm:ss)\n" "$runfile" $((DURATION/60)) $((DURATION%60)) \
        | tee -a "$WORKDIR/timing.log"

done

# =====================================================
# === TOTAL TIME =======================================
# =====================================================

END_TOTAL=$(date +%s)
TOTAL_TIME=$((END_TOTAL - START_TOTAL))

echo "=== TOTAL PROCESSING TIME ===" | tee -a "$WORKDIR/timing.log"
printf "TOTAL: %02d:%02d (mm:ss)\n" $((TOTAL_TIME/60)) $((TOTAL_TIME%60)) \
    | tee -a "$WORKDIR/timing.log"

echo "=== DONE ==="