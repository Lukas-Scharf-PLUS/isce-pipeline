# isce-pipeline
this builds a docker image for using ISCE 



For local usage:

docker run --rm \
  -v ~/projects/ADUCAT/data:/data \

  # =========================
  # === REQUIRED ============
  # =========================
  -e OUTPUT_DIR=/data \
  -e DATA_DIR=/data/ASF_SLC/Ascending_73 \
  -e ORB_DIR=/data/orbits_Sentinel-1 \
  -e DEM=/data/DEM/DEM_30m.wgs84.dem \
  -e REF_DATE=20200616 \

  # =========================
  # === OPTIONAL TIME RANGE =
  # =========================
  -e START_DATE=20200101 \
  -e END_DATE=20200630 \

  # =========================
  # === AOI =================
  # =========================
  -e "48.17229133 48.2238674 16.34362814 16.37115647" \

  # =========================
  # === PROCESSING PARAMS ===
  # =========================
  -e C=2 \
  -e Z=2 \
  -e R=6 \
  -e F=0.5 \

  # =========================
  # === PARALLELIZATION (also optional) =====
  # =========================
  -e NUM_PROC=4 \
  -e OMP_THREADS=2 \

  # =========================
  # === OPTIONAL PATHS ======
  # =========================
  -e AUX_DIR=/data/aux \

  # =========================
  # === RUN IMAGE ===========
  # =========================
  isce-stack:0.1.0 \
  /scripts/run_stackSentinel.sh



🧪 Minimal / lightweight test run
docker run --rm \
  -v ~/projects/ADUCAT/data:/data \
  -e OUTPUT_DIR=/data \
  -e DATA_DIR=/data/ASF_SLC/Ascending_73 \
  -e ORB_DIR=/data/orbits_Sentinel-1 \
  -e DEM=/data/DEM/DEM_30m.wgs84.dem \
  -e REF_DATE=20200616 \
  -e START_DATE=20200610 \
  -e END_DATE=20200622 \
  -e BBOX="48.20 48.21 16.35 16.36" \
  -e C=1 \
  -e Z=1 \
  -e R=2 \
  -e F=0.3 \
  -e NUM_PROC=2 \
  -e OMP_THREADS=3 \
  isce-stack:0.1.1 \
  /scripts/run_stackSentinel.sh