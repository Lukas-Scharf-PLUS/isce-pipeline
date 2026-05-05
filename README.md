# isce-pipeline
this builds a docker image for using ISCE 



For local usage:

docker run --rm \
  -v ~/projects/ADUCAT/data:/data \

  === optional ====================
   
  stage1 - run_file_01-run_file_10 
  stage2 - run_file_11-run_file_15
  stage3 - run_file_16
  ==================================

  -e STAGE=stage1

  === REQUIRED ======================

  -e OUTPUT_DIR=/data \
  -e DATA_DIR=/data/ASF_SLC/Ascending_73 \
  -e ORB_DIR=/data/orbits_Sentinel-1 \
  -e DEM=/data/DEM/DEM_30m.wgs84.dem \
  -e REF_DATE=20200616 \

  === AOI =============================

  -e "48.17229133 48.2238674 16.34362814 16.37115647" \


  === PROCESSING PARAMS ==========

  -e C=2 \
  -e Z=2 \
  -e R=6 \
  -e F=0.5 \

  
  === PARALLELIZATION (also optional) =====
  -e NUM_PROC=4 \
  -e OMP_THREADS=2 \


  === OPTIONAL PATHS ======
  -e AUX_DIR=/data/aux \

 
  === RUN IMAGE ===========
  isce-stack:0.1.0 \
  /scripts/run_stackSentinel.sh



🧪 Minimal / lightweight test run
docker run --rm   
-v ~/projects/ADUCAT/data:/data 
-e STAGE=stage1    
-e OUTPUT_DIR=/data/   
-e DATA_DIR=/data/ASF_SLC/Ascending_73   
-e ORB_DIR=/data/orbits_Sentinel-1  
-e DEM=/data/DEM/DEM_30m.wgs84.dem   
-e REF_DATE=20200616   
isce-stack:0.1.5   
/scripts/run_stackSentinel.sh