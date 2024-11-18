#!/bin/sh
#
# Finnish Meteorological Institute / Mikko Aalto (2014)
# Modified by Elmeri Nurmi (2017)
# Adedd pbzip2, rememer to install it.
#
# SmartMet Data Ingestion Module for WRF Model

#. /smartmet/cnf/data/wrf.cnf

AREA=rwanda
DOMAIN=d02
OUT=/smartmet/data/wrf/$AREA
CNF=/smartmet/run/data/wrf/cnf
EDITOR=/smartmet/editor/in

#Check the input
if [ $# -ne 2 ];
then
  echo " RUN [00,06,12,18] and domain [d01,d02] ?"
  exit 0
fi

RUN=$1
DOMAIN=$2

if [ $DOMAIN = d01 ]
then
  PRODUCER=61
  DOMAINNAME=large
else 
  PRODUCER=60
  DOMAINNAME=small
fi

#UTCHOUR=$(date -u +%H -d '-3 hours')
UTCHOUR=$(date -u +%H)
DATE=$(date -u +%Y%m%d${RUN} -d '-9 hours')
#DATE=2024091812
#DATE=$(date -u +%Y%m%d${RUN}00)
#FILEDATE=$(date -u +%y%m%d${RUN}00 -d '-3 hours')
#FILEDATE=$(date -u +%y%m%d${RUN}00)
#FILEDATE=$(date -u +%y%m%d${RUN2}00)
TMP=/smartmet/tmp/data/wrf/$AREA/$DOMAIN/$DATE/
LOGFILE=/smartmet/logs/data/wrf${DOMAIN}_${RUN}.log
OUTNAME=${DATE}00_wrf_${AREA}_${DOMAINNAME}

# Log everything
exec &> $LOGFILE

echo $(date)

mkdir -p $OUT/surface/querydata
mkdir -p $OUT/pressure/querydata

# Check that we don't already have this analysis time
if [ -e $OUT/surface/querydata/${OUTNAME}_surface.sqd ]; then
    echo Model for time $DATE exists already!
    exit 0
fi

mkdir -p $TMP/grib

cd $TMP/grib

mkdir -p /smartmet/data/incoming/wrf/${DOMAIN}/${DATE}

echo "Moving files from incoming...."
#mv /smartmet/data/incoming/wrf/${DOMAIN}/${FILEDATE}*${DOMAIN}.grb2* .
mv /smartmet/data/incoming/wrf/${DOMAIN}/${DATE}/WRFPRS* .
if [ $? -ne 0 ]
then
    echo "error with mv to tmp"
fi
echo "done"
#

echo "Analysis time: $DATE"
echo "Model Run: $RUN"

echo "Converting grib files to qd files..."
#gribtoqd -n -t -L 1,2,10,100,101,103,105,200 -p "${PRODUCER},WRF Surface,WRF Pressure" -o $TMP/${OUTNAME}.sqd $TMP/grib/
#gribtoqd -n -t -L 1,100 -p "${PRODUCER},WRF Surface,WRF Pressure" -o $TMP/${OUTNAME}.sqd $TMP/grib/
# Surface parameters
gribtoqd -d -c $CNF/wrf_surface.cnf -n -t -L 1 -p "${PRODUCER},WRF Surface" -o $TMP/${OUTNAME}.sqd $TMP/grib/
# Pressure levels
gribtoqd -d -c $CNF/wrf_pressure.cnf -n -t -L 100 -p "${PRODUCER},WRF Pressure" -o $TMP/${OUTNAME}.sqd $TMP/grib/
echo "done"

echo "Analysis time: $DATE"
echo "Model Run: $RUN"

echo "Converting grib files to qd files..."
#gribtoqd -n -t -L 1,2,10,100,101,103,105,200 -p "${PRODUCER},WRF Surface,WRF Pressure" -o $TMP/${OUTNAME}.sqd $TMP/grib/
#gribtoqd -n -t -L 1,100 -p "${PRODUCER},WRF Surface,WRF Pressure" -o $TMP/${OUTNAME}.sqd $TMP/grib/
# Surface parameters
gribtoqd -d -c $CNF/wrf_surface.cnf -n -t -L 1 -p "${PRODUCER},WRF Surface" -o $TMP/${OUTNAME}.sqd $TMP/grib/
# Pressure levels
gribtoqd -d -c $CNF/wrf_pressure.cnf -n -t -L 100 -p "${PRODUCER},WRF Pressure" -o $TMP/${OUTNAME}.sqd $TMP/grib/
echo "done"


# Postproces surface
qdscript -a 1,353 -i $TMP/${OUTNAME}.sqd_levelType_1 $CNF/wrf_surface.st > $TMP/${OUTNAME}.sqd_levelType_1_tmp
qdset -n "Pressure Reduced To MSL (prmsl)" $TMP/${OUTNAME}.sqd_levelType_1_tmp 1
qdset -n "Precipitation mm/h" $TMP/${OUTNAME}.sqd_levelType_1_tmp 353


# Takin the surface and pressure data
mv -f $TMP/$OUTNAME.sqd_levelType_1_tmp $TMP/${OUTNAME}_surface.sqd.tmp
mv -f $TMP/$OUTNAME.sqd_levelType_100 $TMP/${OUTNAME}_pressure.sqd.tmp

#
# Create querydata totalWind and WeatherAndCloudiness objects
#echo -n "Creating Wind objects:..."
qdversionchange -a 7 < $TMP/${OUTNAME}_surface.sqd.tmp > $TMP/${OUTNAME}_surface.sqd
echo "done"
qdversionchange -w 0 7 < $TMP/${OUTNAME}_pressure.sqd.tmp > $TMP/${OUTNAME}_pressure.sqd

# Crop unnecessary parameters
#echo -n "Cropping parameters..."

#Modified qdcrop -command by removing param 326. This script should be renewed so
#that conversion is done only for parameters actually exists in the grib-file
#Now it tries to convert all and removes unwanted parameters.
#qdcrop -p 1,4,10,13,19,50,51,59,66,281,326,407,472 $TMP/${OUTNAME}_surface.sqd.NO_CROP $TMP/${OUTNAME}_surface.sqd
#qdcrop -p 1,4,10,13,19,50,51,59,66,281,407,472 $TMP/${OUTNAME}_surface.sqd.NO_CROP $TMP/${OUTNAME}_surface.sqd
#qdcrop -p 2,4,8,13,19,43 -l 100,150,200,250,300,350,400,450,500,550,600,650,700,750,800,850,900,925,950,1000 $TMP/${OUTNAME}_pressure.sqd.NO_CROP $TMP/${OUTNAME}_pressure.sqd
#echo "done"

# Correct the Origin time for d02(small) domain.
if [ $DOMAIN = d02 ]; then
  echo -n "Changing origin time (${DATE}) for d02 files"
  qdset -T ${DATE}00 $TMP/${OUTNAME}_surface.sqd
  qdset -T ${DATE}00 $TMP/${OUTNAME}_pressure.sqd
else
  echo -n "No need to change origin time for d01 files"
fi

#
# Copy files to SmartMet Workstation and SmartMet Production directories
#

if [ -s $TMP/${OUTNAME}_surface.sqd ]; then
    echo -n "Compressing with pbzip2..."
    pbzip2 -p8 -k $TMP/${OUTNAME}_surface.sqd & pbzip2 -p8 -k $TMP/${OUTNAME}_pressure.sqd
    echo "done"

    echo -n "Copying file to SmartMet Production..."
    mv -f $TMP/${OUTNAME}_surface.sqd $OUT/surface/querydata/${OUTNAME}_surface.sqd
    #cp -f $OUT/surface/querydata/${OUTNAME}_surface.sqd $EDITOR/${OUTNAME}_surface.sqd
    mv -f $TMP/${OUTNAME}_surface.sqd.bz2 $EDITOR/
    echo "done"
    echo "Created files: ${OUTNAME}_surface.sqd"
    echo -n "Copying file to SmartMet Production..."
    mv -f $TMP/${OUTNAME}_pressure.sqd $OUT/pressure/querydata/${OUTNAME}_pressure.sqd
    #cp -f $OUT/pressure/querydata/${OUTNAME}_pressure.sqd $EDITOR/${OUTNAME}_pressure.sqd
    mv -f $TMP/${OUTNAME}_pressure.sqd.bz2 $EDITOR/
    echo "done"
    echo "Created files: ${OUTNAME}_pressure.sqd"
fi

# Clean up the mess
rm -rf $TMP

echo $(date)

