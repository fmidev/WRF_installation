#!/bin/bash

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# ===============================================
# Clean old data
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

# Clean main run directories
find $BASE_DIR/GFS -type f -ctime +0 | xargs -r rm
find $BASE_DIR/GFS -mindepth 1 -type d -empty -delete
find $BASE_DIR/ECMWF -type f -ctime +0 | xargs -r rm
find $BASE_DIR/ECMWF -mindepth 1 -type d -empty -delete
find "$BASE_DIR/DA_input" \( -path "$BASE_DIR/DA_input/be" -prune \) -o -type f -ctime +2 | xargs -r rm
find $BASE_DIR/ob/wrf_obs -mindepth 1 -type d -empty -delete
find $BASE_DIR/out -type f -ctime +2 -o -type l -ctime +2 | xargs -r rm
find $BASE_DIR/out -mindepth 1 -type d -empty -delete
find $BASE_DIR/UPP_out -type f -ctime +5 | xargs -r rm
find $BASE_DIR/UPP_out -mindepth 1 -type d -empty -delete
find $BASE_DIR/Verification/Data/Obs -type f -ctime +0 | xargs -r rm
find $BASE_DIR/Verification/Data/Forecast -type f -ctime +0 | xargs -r rm
find $BASE_DIR/Verification/Results -type f -ctime +750 | xargs -r rm

# Clean WRF_test directories if they exist
TEST_BASE_DIR=$(dirname $BASE_DIR)/WRF_test
if [ -d "$TEST_BASE_DIR" ]; then
    find $TEST_BASE_DIR/DA_input -type f -ctime +2 | xargs -r rm
    find $TEST_BASE_DIR/out -type f -ctime +2 -o -type l -ctime +2 | xargs -r rm
    find $TEST_BASE_DIR/out -mindepth 1 -type d -empty -delete
fi