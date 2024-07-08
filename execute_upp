#!/bin/bash

anhour=$1
year=`date "+%Y"`; month=`date "+%m"`;day=`date "+%d"`; hour=$anhour

cp /home/user/out/$year$month$day$hour/wrfout_d0* /home/user/UPP_wrk/wrfprd/

cd /home/user/UPP_wrk/postprd

if [ $hour==00 -o $hour==12 ]; then
  sed -i "s/\(export startdate=\)[0-9]\{10\}/\1${year}${month}${day}${hour}/" run_unipost
  sed -i "s/\(export fhr=\)[0-9]\{2\}/\1${hour}/" run_unipost
  sed -i "s/\(export lastfhr=\)[0-9]\{2\}/\148/" run_unipost
  ./run_unipost

else
  echo "UPP for Analysis time $hour is not selected"
  exit
fi

mkdir -p /home/user/UPP_out/${year}${month}${day}${hour}
cp /home/user/UPP_wrk/postprd/WRFPRS_d0* /home/user/UPP_out/${year}${month}${day}${hour}/

#cleaning wrk dirs
rm /home/user/UPP_wrk/wrfprd/wrfout_d0*
rm /home/user/UPP_wrk/postprd/WRFPRS_d0*

echo "UPP done"
