#!/bin/bash

# ===============================================
# WRF Control Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

hour=$1

# Set the date based on the hour for daily runs
# If the hour is 18, adjust the date to yesterday
if [ $hour -eq 18 ]; then
  year=$(date "+%Y" -d "yesterday")
  month=$(date "+%m" -d "yesterday")
  day=$(date "+%d" -d "yesterday")
else
  year=$(date "+%Y")
  month=$(date "+%m")
  day=$(date "+%d")
fi

# Change to the main directory
cd ${MAIN_DIR}

# Log the start of the process
echo "*************" > ${MAIN_DIR}/logs/main.log
echo "$year$month$day$hour WRF Run started" >> ${MAIN_DIR}/logs/main.log
date >> ${MAIN_DIR}/logs/main.log

# Initialize variables for checking boundary files
files_found=false


# ===============================================
# Step 1: Check boundary files
# ===============================================
if [ "$RUN_CHECK_BOUNDARY_FILES" = true ]; then
  echo "1) Checking for boundary files before running ems_prep:" >> ${MAIN_DIR}/logs/main.log
  echo "   $(date +"%H:%M %Y%m%d")" >> ${MAIN_DIR}/logs/main.log

  for ((i=1; i<=15; i++)); do
    # Count the number of GRIB files in the directory
    file_count=$(find "$DATA_DIR/$year$month$day$hour" -maxdepth 1 -type f -name "gfs.t${hour}z.pgrb2.0p25.f*" | wc -l)
    echo $file_count
    
    if [ "$file_count" -ge "$GRIBNUM" ]; then
      # Files are sufficient, proceed
      echo "Sufficient GRIB files found. Continuing execution." >> ${MAIN_DIR}/logs/main.log
      files_found=true
      break
    else
      # Wait for 5 minutes before retrying
      sleep 300
    fi
  done

  # Exit if the required files are not found after retries
  if [ "$files_found" = false ]; then
    echo "Maximum retries exceeded. Not enough boundary files. Terminating the run!" >> ${MAIN_DIR}/logs/main.log
    echo "   $(date +"%H:%M %Y%m%d")" >> ${MAIN_DIR}/logs/main.log
    exit 1
  fi
fi

# ===============================================
# Step 2: Get observations (optional, needed for data assimilation)
# ===============================================
if [ "$RUN_GET_OBS" = true ]; then
  ./get_obs.sh $year $month $day $hour
  echo "Downloaded observations" >> ${MAIN_DIR}/logs/main.log
  date >> ${MAIN_DIR}/logs/main.log
fi

# ===============================================
# Step 2: Run the WPS
# ===============================================
if [ "$RUN_WPS" = true ]; then
  ./run_WPS.sh $year $month $day $hour $LEADTIME $PROD_DIR
  echo "WPS completed" >> ${MAIN_DIR}/logs/main.log
  date >> ${MAIN_DIR}/logs/main.log
fi

# ===============================================
# Step 3: Run the WRF
# ===============================================
if [ "$RUN_WRF" = true ]; then
  ./run_WRF.sh $year $month $day $hour $LEADTIME $PROD_DIR
  echo "$year$month$day$hour WRF Run finished" >> ${MAIN_DIR}/logs/main.log
  date >> ${MAIN_DIR}/logs/main.log

  # Log a key output message from the WRF run
  tail -2 ${PROD_DIR}/$year$month$day$hour/rsl.out.0000 | head -1 >> ${MAIN_DIR}/logs/main.log
fi

# ===============================================
# Step 4: Run the UPP (NetCDF -> GRIB) 
# ===============================================
if [ "$RUN_UPP" = true ]; then
  echo "Converting NetCDF to GRIB with UPP" >> ${MAIN_DIR}/logs/main.log
  ./execute_upp.sh $hour
fi

# ===============================================
# Step 5: Run the Verification 
# ===============================================
if [ "$RUN_VERIFICATION" = true ]; then
  echo "Starting verification process"
  cd $VERIFICATION_DIR
  ./verification.sh $year $month $day $hour
fi

# ===============================================
# Step 6: Copy GRIB files to SmartMet 
# ===============================================
if [ "$RUN_COPY_GRIB" = true ]; then
  echo "Copying GRIB files to SmartMet for visualization"
  rsync -e ssh -av --include='*/' --include="*d01*" --exclude="*" $BASE_DIR/UPP_out/$year$month$day$hour smartmet@10.10.233.145:/smartmet/data/incoming/wrf/d01/
  rsync -e ssh -av --include='*/' --include="*d02*" --exclude="*" $BASE_DIR/UPP_out/$year$month$day$hour smartmet@10.10.233.145:/smartmet/data/incoming/wrf/d02/
fi

echo "WRF Run completed successfully! All tasks finished." >> ${MAIN_DIR}/logs/main.log
echo "FINISHED !! WE ARE FREE NOW !! YEAH"
