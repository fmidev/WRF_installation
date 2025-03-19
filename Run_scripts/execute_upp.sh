#!/bin/bash

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# ===============================================
# Execute UPP postprocessing tool
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

year=$1
month=$2
day=$3
hour=$4

cp $BASE_DIR/out/$year$month$day$hour/wrfout_d0* $BASE_DIR/UPP_wrk/wrfprd/
cd $BASE_DIR/UPP_wrk/postprd

sed -i "s/\(export startdate=\)[0-9]\{10\}/\1${year}${month}${day}${hour}/" run_unipost
./run_unipost

  
mkdir -p $BASE_DIR/UPP_out/${year}${month}${day}${hour}
cp $BASE_DIR/UPP_wrk/postprd/WRFPRS_d0* $BASE_DIR/UPP_out/${year}${month}${day}${hour}/

#cleaning wrk dirs
rm $BASE_DIR/UPP_wrk/wrfprd/wrfout_d0*
rm $BASE_DIR/UPP_wrk/postprd/WRFPRS_d0*

echo "UPP done"
