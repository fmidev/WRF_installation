#!/bin/bash

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# ===============================================
# Clean old data
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

find $BASE_DIR/GFS -type f -ctime +0 | xargs -r rm
find $BASE_DIR/GFS -mindepth 1 -type d -empty -delete
find $BASE_DIR/DA_input/rc -type f -ctime +2 -name "*wrfout*" | xargs -r rm
find $BASE_DIR/DA_input/ob/raw_obs -type f -ctime +1 | xargs -r rm
find $BASE_DIR/out -type f -ctime +2 -o -type l -ctime +2 | xargs -r rm 
find $BASE_DIR/out -mindepth 1 -type d -empty -delete 
find $BASE_DIR/UPP_out -type f -ctime +5 | xargs -r rm
find $BASE_DIR/UPP_out -mindepth 1 -type d -empty -delete