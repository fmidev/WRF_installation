#!/bin/bash

# ===============================================
# WRF Control Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# Set the date based on the UTC hour for daily runs
hour=$1
DATE=$(date -u -d "today ${hour}:00" +%Y%m%d)

if [ "$(date -u +%s)" -lt "$(date -u -d "today ${hour}:00" +%s)" ]; then
  DATE=$(date -u -d "yesterday ${hour}:00" +%Y%m%d)
fi

year=${DATE:0:4}
month=${DATE:4:2}
day=${DATE:6:2}

# Change to the script directory
cd ${MAIN_DIR}

# Log the start of the process
start_time=$(date +%s)
echo "*************" > ${BASE_DIR}/logs/main.log
echo "$year$month$day$hour WRF Run started" >> ${BASE_DIR}/logs/main.log
date >> ${BASE_DIR}/logs/main.log

# Initialize variables for checking boundary files
files_found=false


# ===============================================
# Step 1: Check boundary files
# ===============================================
if [ "$RUN_CHECK_BOUNDARY_FILES" = true ]; then
  echo "1) Checking for boundary files before running ems_prep:" >> ${BASE_DIR}/logs/main.log
  echo "   $(date +"%H:%M %Y%m%d")" >> ${BASE_DIR}/logs/main.log
  echo "   Boundary source: ${BOUNDARY_SOURCE:-GFS}" >> ${BASE_DIR}/logs/main.log

  for ((i=1; i<=20; i++)); do
    # Check boundary files based on source
    if [ "${BOUNDARY_SOURCE}" = "ECMWF" ]; then
      # Check ECMWF files
      file_count=$(find "${DATA_DIR_ECMWF}/$year$month$day$hour" -maxdepth 1 -type f -name "*.grib2" 2>/dev/null | wc -l)
      
      # Check if conversion is complete for ECMWF files
      if [ -f "${DATA_DIR_ECMWF}/$year$month$day$hour/.converted" ]; then
        conversion_done=true
      else
        conversion_done=false
      fi
      
      if [ "$file_count" -ge "$GRIBNUM" ] && [ "$conversion_done" = true ]; then
        echo "Sufficient ECMWF GRIB files found ($file_count) and conversion complete. Continuing execution." >> ${BASE_DIR}/logs/main.log
        files_found=true
        break
      elif [ "$file_count" -ge "$GRIBNUM" ] && [ "$conversion_done" = false ]; then
        echo "ECMWF files found but conversion not complete. Waiting..." >> ${BASE_DIR}/logs/main.log
        sleep 300
      else
        echo "Waiting for ECMWF files... (found $file_count, need $GRIBNUM)" >> ${BASE_DIR}/logs/main.log
        sleep 300
      fi
    else
      # Check GFS files (default)
      file_count=$(find "${DATA_DIR_GFS:-$DATA_DIR}/$year$month$day$hour" -maxdepth 1 -type f -name "gfs.t${hour}z.pgrb2.0p25.f*" 2>/dev/null | wc -l)
      
      if [ "$file_count" -ge "$GRIBNUM" ]; then
        # Files are sufficient, proceed
        echo "Sufficient GFS GRIB files found ($file_count). Continuing execution." >> ${BASE_DIR}/logs/main.log
        files_found=true
        break
      else
        echo "Waiting for GFS files... (found $file_count, need $GRIBNUM)" >> ${BASE_DIR}/logs/main.log
        # Wait for 5 minutes before retrying
        sleep 300
      fi
    fi
  done

  # Exit if the required files are not found after retries
  if [ "$files_found" = false ]; then
    echo "Maximum retries exceeded. Not enough boundary files. Terminating the run!" >> ${BASE_DIR}/logs/main.log
    echo "   $(date +"%H:%M %Y%m%d")" >> ${BASE_DIR}/logs/main.log
    exit 1
  fi
fi

# ===============================================
# Step 2: Get observations (optional, needed for data assimilation)
# ===============================================
if [ "$RUN_GET_OBS" = true ]; then
  ./get_obs.sh $year $month $day $hour
  echo "Downloaded observations" >> ${BASE_DIR}/logs/main.log
  date >> ${BASE_DIR}/logs/main.log
fi

# ===============================================
# Step 2: Run the WPS
# ===============================================
if [ "$RUN_WPS" = true ]; then
  ./run_WPS.sh $year $month $day $hour $LEADTIME
  echo "WPS completed" >> ${BASE_DIR}/logs/main.log
  date >> ${BASE_DIR}/logs/main.log
fi

# ===============================================
# Step 3: Run the WRF
# ===============================================
if [ "$RUN_WRF" = true ]; then
  ./run_WRF.sh $year $month $day $hour $LEADTIME
  echo "$year$month$day$hour WRF Run finished" >> ${BASE_DIR}/logs/main.log
  date >> ${BASE_DIR}/logs/main.log

  # Log a key output message from the WRF run
  tail -2 ${PROD_DIR}/$year$month$day$hour/rsl.out.0000 | head -1 >> ${BASE_DIR}/logs/main.log
fi

# ===============================================
# Step 4: Run the UPP (NetCDF -> GRIB) 
# ===============================================
if [ "$RUN_UPP" = true ]; then
  echo "Converting NetCDF to GRIB with UPP" >> ${BASE_DIR}/logs/main.log
  ./execute_upp.sh $year $month $day $hour
fi

# ===============================================
# Step 5: Copy GRIB files to SmartMet 
# ===============================================
if [ "$RUN_COPY_GRIB" = true ]; then
  echo "Copying GRIB files to SmartMet for visualization" >> ${BASE_DIR}/logs/main.log
  rsync -e ssh -av --include='*/' --include="*d01*" --exclude="*" $BASE_DIR/UPP_out/$year$month$day$hour smartmet@ip-address:/smartmet/data/incoming/wrf/d01/
  rsync -e ssh -av --include='*/' --include="*d02*" --exclude="*" $BASE_DIR/UPP_out/$year$month$day$hour smartmet@ip-address:/smartmet/data/incoming/wrf/d02/
  ssh smartmet@ip-address /smartmet/bin/ingest-model.sh -m wrf -a large # For larger domain d01
  ssh smartmet@ip-address /smartmet/bin/ingest-model.sh -m wrf -a small # For smaller domain d02
fi

# ===============================================
# Step 6: Run the Verification 
# ===============================================
if [ "$RUN_VERIFICATION" = true ]; then
  echo "Starting verification process"
  ./verification.sh $year $month $day $hour
fi

echo "WRF Run completed successfully! All tasks finished." >> ${BASE_DIR}/logs/main.log
echo "FINISHED !! WE ARE FREE NOW !! YEAH"

# Log the end time and duration of the run
end_time=$(date +%s)
run_duration=$(( (end_time - start_time) / 60 ))
echo "Run $hour started at: $(date -d @$start_time)" >> ${BASE_DIR}/logs/historical.log
echo "Run $hour ended at: $(date -d @$end_time)" >> ${BASE_DIR}/logs/historical.log
echo "Run $hour duration: $run_duration minutes" >> ${BASE_DIR}/logs/historical.log
echo "----------------------------------------" >> ${BASE_DIR}/logs/historical.log
