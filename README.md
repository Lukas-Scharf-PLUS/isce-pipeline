docker run --rm \
  -v ~/projects/ADUCAT/data:/data \

  ###  optional: stage selection (stage1 | stage2 | stage3)
  -e STAGE=stage1 \

  ### required
  -e OUTPUT_DIR=/data \
  -e DATA_DIR=/data/ASF_SLC/Ascending_73 \
  -e ORB_DIR=/data/orbits_Sentinel-1 \
  -e DEM=/data/DEM/DEM_30m.wgs84.dem \
  -e REF_DATE=20200616 \

  ### AOI: "lat_min lat_max lon_min lon_max"
  -e AOI="48.17229133 48.2238674 16.34362814 16.37115647" \

  ### processing params
  -e C=2 \
  -e Z=2 \
  -e R=6 \
  -e F=0.5 \

  ### optional: parallelization
  -e NUM_PROC=4 \
  -e OMP_THREADS=2 \

  ### paths
  -e AUX_DIR=/data/aux \

  ### run
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