#!/bin/bash

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

cp /home/wrf/WRF_Model/out/$year$month$day$hour/wrfout_d0* /home/wrf/WRF_Model/UPP_wrk/wrfprd/
cd /home/wrf/WRF_Model/UPP_wrk/postprd

sed -i "s/\(export startdate=\)[0-9]\{10\}/\1${year}${month}${day}${hour}/" run_unipost
#sed -i "s/\(export fhr=\)[0-9]\{2\}/\100/" run_unipost
#sed -i "s/\(export lastfhr=\)[0-9]\{2\}/\1120/" run_unipost
./run_unipost

  
mkdir -p /home/wrf/WRF_Model/UPP_out/${year}${month}${day}${hour}
cp /home/wrf/WRF_Model/UPP_wrk/postprd/WRFPRS_d0* /home/wrf/WRF_Model/UPP_out/${year}${month}${day}${hour}/

#cleaning wrk dirs
rm /home/wrf/WRF_Model/UPP_wrk/wrfprd/wrfout_d0*
rm /home/wrf/WRF_Model/UPP_wrk/postprd/WRFPRS_d0*

echo "UPP done"
