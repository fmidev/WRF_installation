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

is_valid_grib_file() {
  local file_path="$1"

  # Must exist and be non-empty.
  if [ ! -s "$file_path" ]; then
    return 1
  fi

  # Prefer a real GRIB decode check when tools are available.
  if command -v wgrib2 >/dev/null 2>&1; then
    wgrib2 "$file_path" -s >/dev/null 2>&1
    return $?
  fi

  if command -v grib_ls >/dev/null 2>&1; then
    grib_ls "$file_path" >/dev/null 2>&1
    return $?
  fi

  return 0
}

wait_for_ecmwf_conversion() {
  local boundary_dir="$1"
  local conversion_wait_seconds=1800
  local conversion_check_interval=120
  local waited_seconds=0

  if [ -f "${boundary_dir}/.converted" ]; then
    echo "All required ECMWF boundary files are present and valid up to +${LEADTIME}h. Conversion complete." >> ${BASE_DIR}/logs/main.log
    return 0
  fi

  echo "All required ECMWF boundary files are present and valid up to +${LEADTIME}h, but conversion marker is missing." >> ${BASE_DIR}/logs/main.log
  echo "Waiting up to 30 minutes for ${boundary_dir}/.converted (check interval: 2 minutes)." >> ${BASE_DIR}/logs/main.log

  while [ $waited_seconds -lt $conversion_wait_seconds ]; do
    if [ -f "${boundary_dir}/.converted" ]; then
      echo "ECMWF conversion marker detected. Continuing execution." >> ${BASE_DIR}/logs/main.log
      return 0
    fi

    remaining_minutes=$(( (conversion_wait_seconds - waited_seconds) / 60 ))
    echo "ECMWF conversion marker not found yet. Retrying in ${conversion_check_interval}s (remaining time: ${remaining_minutes} min)." >> ${BASE_DIR}/logs/main.log
    sleep $conversion_check_interval
    waited_seconds=$((waited_seconds + conversion_check_interval))
  done

  echo "ERROR: ECMWF conversion marker ${boundary_dir}/.converted not found within 30 minutes. Terminating the run." >> ${BASE_DIR}/logs/main.log
  return 1
}

# ===============================================
# Step 1: Check boundary files
# ===============================================
if [ "$RUN_CHECK_BOUNDARY_FILES" = true ]; then
  echo "1) Checking for boundary files before running ems_prep:" >> ${BASE_DIR}/logs/main.log
  echo "   $(date +"%H:%M %Y%m%d")" >> ${BASE_DIR}/logs/main.log
  echo "   Boundary source: ${BOUNDARY_SOURCE:-GFS}" >> ${BASE_DIR}/logs/main.log

  i=1
  while [ "$i" -le 20 ]; do
    missing_files=""
    invalid_files=""

    # Check boundary files based on source
    if [ "${BOUNDARY_SOURCE}" = "ECMWF" ]; then
      boundary_dir="${DATA_DIR_ECMWF}/$year$month$day$hour"

      fh=0
      while [ "$fh" -le "$LEADTIME" ]; do
        expected_pattern="${boundary_dir}/${year}${month}${day}${hour}0000-${fh}h-*-fc.grib2"
        matched_file=$(compgen -G "$expected_pattern" | head -n1)

        if [ -z "$matched_file" ]; then
          missing_files+=" f${fh}"
        elif ! is_valid_grib_file "$matched_file"; then
          invalid_files+=" ${matched_file}"
        fi
        fh=$((fh + 3))
      done

      if [ -z "$missing_files" ] && [ -z "$invalid_files" ]; then
        if wait_for_ecmwf_conversion "$boundary_dir"; then
          files_found=true
          break
        else
          exit 1
        fi
      else
        if [ -n "$missing_files" ]; then
          echo "Waiting for ECMWF files. Missing forecast hours:${missing_files}" >> ${BASE_DIR}/logs/main.log
        fi
        if [ -n "$invalid_files" ]; then
          echo "Waiting for ECMWF files. Invalid/corrupted files:${invalid_files}" >> ${BASE_DIR}/logs/main.log
        fi
        sleep 300
      fi
    else
      # Check GFS files (default)
      boundary_dir="${DATA_DIR_GFS}/$year$month$day$hour"

      fh=0
      while [ "$fh" -le "$LEADTIME" ]; do
        fhr=$(printf "%03d" "$fh")
        expected_file="${boundary_dir}/gfs.t${hour}z.pgrb2.0p25.f${fhr}"

        if [ ! -f "$expected_file" ]; then
          missing_files+=" f${fhr}"
        elif ! is_valid_grib_file "$expected_file"; then
          invalid_files+=" ${expected_file}"
        fi
        fh=$((fh + 3))
      done

      if [ -z "$missing_files" ] && [ -z "$invalid_files" ]; then
        echo "All required GFS boundary files are present and valid up to +${LEADTIME}h." >> ${BASE_DIR}/logs/main.log
        files_found=true
        break
      else
        if [ -n "$missing_files" ]; then
          echo "Waiting for GFS files. Missing forecast hours:${missing_files}" >> ${BASE_DIR}/logs/main.log
        fi
        if [ -n "$invalid_files" ]; then
          echo "Waiting for GFS files. Invalid/corrupted files:${invalid_files}" >> ${BASE_DIR}/logs/main.log
        fi
        sleep 300
      fi
    fi
    i=$((i + 1))
  done

  # Exit if the required files are not found after retries
  if [ "$files_found" = false ]; then
    echo "Maximum retries exceeded. Required boundary files are still missing or invalid. Terminating the run!" >> ${BASE_DIR}/logs/main.log
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
