

# Local runs:

## fetch and normalize orbits

cd ~/projects/ADUCAT

docker run --rm \
  --env-file .env_cdse \
  -v $(pwd)/data:/data \
  -w /data \
  -e SLC_DIR="/data/ASF_SLC/Ascending_73" \
  -e ORB_DIR="/data/orbits" \
  ghcr.io/lukas-scharf-plus/isce-stack:0.1.7 \
  bash -c "
    /scripts/fetch_orbits.sh &&
    /scripts/normalize_orbit_layout.sh /data/orbits /data/orbits_isce true
  "

docker run --rm \
  -v $(pwd)/data:/data \
  -w /data \
  -e START_DATE=20200603 \
  -e END_DATE=20200630 \
  -e ORB_DIR="/data/orbits" \
  -e CDSE_USERNAME='...' \
  -e CDSE_PASSWORD='...' \
  ghcr.io/lukas-scharf-plus/isce-stack:0.1.7 \
  bash -c "
    /scripts/fetch_orbits.sh &&
    /scripts/normalize_orbit_layout.sh /data/orbits /data/orbits_isce 
  "


Explaination for arguments in normalize_orbit_layout.sh:
it will copy orbit file from /data/orbits to /data/orbits_isce and the underlying folder structure.
When adding true after it, it will delete the original /data/orbits folder. 



## stackSentinel.sh

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
docker run --rm \
  -v ~/projects/ADUCAT/data:/data \
  -e OUTPUT_DIR=/data/ \
  -e DATA_DIR=/data/ASF_SLC/Ascending_73 \
  -e ORB_DIR=/data/orbits_Sentinel-1 \
  -e DEM=/data/DEM/DEM_30m.wgs84.dem \
  -e AUX_DIR=/data/aux \
  -e AOI="48.17229133 48.2238674 16.34362814 16.37115647" \
  -e REF_DATE=20200616 \
  -e C=2 \
  -e Z=2 \
  -e R=6 \
  -e F=0.5 \
  ghcr.io/lukas-scharf-plus/isce-stack:0.1.7 \
  /scripts/run_stackSentinel.sh