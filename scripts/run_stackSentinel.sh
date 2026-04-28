#!/bin/bash
set -euo pipefail

echo "=== stackSentinel entrypoint ==="

# =========================
# === REQUIRED PARAMS =====
# =========================

: "${OUTPUT_DIR:?OUTPUT_DIR is required}"
: "${DATA_DIR:?DATA_DIR is required}"
: "${ORB_DIR:?ORB_DIR is required}"
: "${DEM:?DEM is required}"

# optional but usually needed
: "${AUX_DIR:=${BASE_DIR}/aux}"

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

# =========================
# === THREAD CONTROL ======
# =========================
export OMP_NUM_THREADS="$OMP_THREADS"
export OPENBLAS_NUM_THREADS="$OMP_THREADS"
export MKL_NUM_THREADS="$OMP_THREADS"


# =========================
# === OPTIONAL SUBSET =====
# =========================
ORIG_DATA_NAME=$(basename "$DATA_DIR")

: "${START_DATE:=}"
: "${END_DATE:=}"

if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then

    echo "Subsetting scenes: $START_DATE → $END_DATE"

    SUBSET_DIR="${BASE_DIR}/subset_${START_DATE}_${END_DATE}"
    rm -rf "$SUBSET_DIR"
    mkdir -p "$SUBSET_DIR"

    for f in "$DATA_DIR"/*; do
        fname=$(basename "$f")
        date=$(echo "$fname" | grep -oE '[0-9]{8}' | head -n1 || true)

        [[ -z "$date" ]] && continue

        if (( date >= START_DATE && date <= END_DATE )); then
            ln -s "$f" "$SUBSET_DIR/$fname"
        fi
    done

    count=$(ls "$SUBSET_DIR" | wc -l)
    if [[ "$count" -eq 0 ]]; then
        echo "ERROR: no scenes in selected date range"
        exit 1
    fi

    echo "Subset created: $SUBSET_DIR"
    DATA_DIR="$SUBSET_DIR"
fi


if [[ -n "$START_DATE" && -n "$END_DATE" ]]; then
    RANGE_TAG="${START_DATE}_${END_DATE}"
else
    RANGE_TAG="all"
fi


# =========================
# === WORKDIR ============
# =========================
WORKDIR="${OUTPUT_DIR}/stack_${ORIG_DATA_NAME}_${RANGE_TAG}_c${C}_z${Z}_r${R}_f${F}"

START_TOTAL=$(date +%s)

# safety check
if [[ -z "$WORKDIR" || "$WORKDIR" == "/" || "$WORKDIR" == "$BASE_DIR" ]]; then
    echo "ERROR: WORKDIR is unsafe!"
    exit 1
fi

# remove current working directory if it already exists
rm -rf -- "$WORKDIR"

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
    echo "BASE_DIR=$BASE_DIR"
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
    df -h "$BASE_DIR" || true
    echo ""

    echo "---- ENV (filtered) ----"
    env | grep -E '^(OMP|MKL|OPENBLAS|NUM_PROC|BASE_DIR|DATA_DIR|WORKDIR)' || true
    echo ""

    echo "====================================="
} | tee "$PARAM_LOG"

# =====================================================
# === RUN stackSentinel.py =============================
# =====================================================

echo "=== Running stackSentinel.py ==="

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

printf "stackSentinel.py took %02d:%02d (mm:ss)\n" $((SS_TIME/60)) $((SS_TIME%60)) \
    | tee -a "$WORKDIR/timing.log"

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