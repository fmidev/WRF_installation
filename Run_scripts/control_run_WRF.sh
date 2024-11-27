#!/bin/bash

# ===============================================
# WRF Control Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

anhour=$1
hour=$anhour

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

# Forecast lead time and directory paths
leadtime=48  # Length of the forecast in hours
main_dir="/home/wrf/WRF_Model/scripts"
prod_dir="/home/wrf/WRF_Model/out"
data_dir="/home/wrf/WRF_Model/GFS"
verification_dir="/home/wrf/WRF_Model/Verification/Scripts"

# Change to the main directory
cd ${main_dir}

# Log the start of the process
echo "*************" > ${main_dir}/logs/main.log
echo "$year$month$day$hour WRF Run started" >> ${main_dir}/logs/main.log
date >> ${main_dir}/logs/main.log

# Initialize variables for checking boundary files
gribnum=20  # Minimum required number of GRIB files
files_found=false

# ===============================================
# Step 1: Check boundary files
# ===============================================
echo "1) Checking for boundary files before running ems_prep:" >> ${main_dir}/logs/main.log
echo "   $(date +"%H:%M %Y%m%d")" >> ${main_dir}/logs/main.log

for ((i=1; i<=15; i++)); do
  # Count the number of GRIB files in the directory
  file_count=$(find "$data_dir/$year$month$day$hour" -maxdepth 1 -type f -name "gfs.t${anhour}z.pgrb2.0p25.f*" | wc -l)
  echo $file_count
  
  if [ "$file_count" -ge "$gribnum" ]; then
    # Files are sufficient, proceed
    echo "Sufficient GRIB files found. Continuing execution." >> ${main_dir}/logs/main.log
    files_found=true
    break
  else
    # Wait for 5 minutes before retrying
    sleep 300
  fi
done

# Exit if the required files are not found after retries
if [ "$files_found" = false ]; then
  echo "Maximum retries exceeded. Not enough boundary files. Terminating the run!" >> ${main_dir}/logs/main.log
  echo "   $(date +"%H:%M %Y%m%d")" >> ${main_dir}/logs/main.log
  exit 1
fi

# ===============================================
# Step 2: Get observations (optional, needed for data assimilation)
# ===============================================
./get_obs.sh $year $month $day $hour
echo "Downloaded observations" >> ${main_dir}/logs/main.log
date >> ${main_dir}/logs/main.log

# ===============================================
# Step 2: Run the WPS
# ===============================================
./run_WPS.sh $year $month $day $hour $leadtime $prod_dir
echo "WPS completed" >> ${main_dir}/logs/main.log
date >> ${main_dir}/logs/main.log

# ===============================================
# Step 3: Run the WRF
# ===============================================
./run_WRF.sh $year $month $day $hour $leadtime $prod_dir
echo "$year$month$day$hour WRF Run finished" >> ${main_dir}/logs/main.log
date >> ${main_dir}/logs/main.log

# Log a key output message from the WRF run
tail -2 ${prod_dir}/$year$month$day$hour/rsl.out.0000 | head -1 >> ${main_dir}/logs/main.log

# ===============================================
# Step 4: Run the UPP (NetCDF -> GRIB) 
# ===============================================
echo "Converting NetCDF to GRIB with UPP" >> ${main_dir}/logs/main.log
./execute_upp.sh $hour

# ===============================================
# Step 5: Run the Verification 
# ===============================================
echo "Starting verification process"
cd $verification_dir
./verification.sh $year $month $day $hour

# ===============================================
# Step 6: Copy GRIB files to SmartMet 
# ===============================================
echo "Copying GRIB files to SmartMet for visualization"
rsync -e ssh -av --include='*/' --include="*d01*" --exclude="*" /home/wrf/WRF_Model/UPP_out/$year$month$day$hour smartmet@10.10.233.145:/smartmet/data/incoming/wrf/d01/
rsync -e ssh -av --include='*/' --include="*d02*" --exclude="*" /home/wrf/WRF_Model/UPP_out/$year$month$day$hour smartmet@10.10.233.145:/smartmet/data/incoming/wrf/d02/
#ssh smartmet@10.10.233.145 /smartmet/run/data/wrf/bin/wrf.sh $hour d01
#ssh smartmet@10.10.233.145 /smartmet/run/data/wrf/bin/wrf.sh $hour d02


echo "WRF Run completed successfully! All tasks finished." >> ${main_dir}/logs/main.log
echo "FINISHED !! WE ARE FREE NOW !! YEAH"
