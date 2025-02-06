#!/bin/bash

# Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# ===============================================
# Execute UPP postprocessing tool
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

anhour=$1
hour=$anhour

# Modify date for 18z
if [ $hour -eq 18 ]
 then
  
  year=`date "+%Y" -d "yesterday"`
  month=`date "+%m" -d "yesterday"`
  day=`date "+%d" -d "yesterday"`

 else
  year=`date "+%Y"`
  month=`date "+%m"`
  day=`date "+%d"`;
fi

cp $BASE_DIR/out/$year$month$day$hour/wrfout_d0* $BASE_DIR/UPP_wrk/wrfprd/
cd $BASE_DIR/UPP_wrk/postprd

sed -i "s/\(export startdate=\)[0-9]\{10\}/\1${year}${month}${day}${hour}/" run_unipost
#sed -i "s/\(export fhr=\)[0-9]\{2\}/\100/" run_unipost
#sed -i "s/\(export lastfhr=\)[0-9]\{2\}/\1120/" run_unipost
./run_unipost

  
mkdir -p $BASE_DIR/UPP_out/${year}${month}${day}${hour}
cp $BASE_DIR/UPP_wrk/postprd/WRFPRS_d0* $BASE_DIR/UPP_out/${year}${month}${day}${hour}/

#cleaning wrk dirs
rm $BASE_DIR/UPP_wrk/wrfprd/wrfout_d0*
rm $BASE_DIR/UPP_wrk/postprd/WRFPRS_d0*

echo "UPP done"
