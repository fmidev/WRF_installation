#!/bin/sh
#
# Finnish Meteorological Institute / Mikko Rauhala (2015-2019)
#
# SmartMet Data Ingestion Module for GFS Model
#

# Load Configuration 
if [ -s /smartmet/cnf/data/gfs.cnf ]; then
    . /smartmet/cnf/data/gfs.cnf
fi

if [ -s gfs.cnf ]; then
    . gfs.cnf
fi

# Setup defaults for the configuration

if [ -z "$AREA" ]; then
    AREA=world
fi

if [ -z "$TOP" ]; then
    TOP=90
fi

if [ -z "$BOTTOM" ]; then
    BOTTOM=-90
fi

if [ -z "$LEFT" ]; then
    LEFT=0
fi

if [ -z "$RIGHT" ]; then
    RIGHT=360
fi

if [ -z "$INTERVALS" ]; then
    INTERVALS=("0 3 126" "132 6 240")
fi

if [ -z "$RESOLUTION" ]; then
    RESOLUTION=0p25
fi

if [-z  "$VALID_HOURS"]; then
    VALID_HOURS="00|06|12|18"
fi

while getopts  "a:b:dg:i:l:r:t:v" flag
do
  case "$flag" in
        a) AREA=$OPTARG;;
        d) DRYRUN=1;;
        g) RESOLUTION=$OPTARG;;
        i) INTERVALS=("$OPTARG");;
        l) LEFT=$OPTARG;;
        r) RIGHT=$OPTARG;;
        t) TOP=$OPTARG;;
        b) BOTTOM=$OPTARG;;
        v) VALID_HOURS=$OPTARG;;
  esac
done

STEP=6
# Model Reference Time
RT=`date -u +%s -d '-3 hours'`
RT="$(( $RT / ($STEP * 3600) * ($STEP * 3600) ))"
RT_HOUR=`date -u -d@$RT +%H`
RT_DATE=`date -u -d@$RT +%Y%m%d`
RT_DATE_HH=`date -u -d@$RT +%Y%m%d%H`
RT_DATE_HHMM=`date -u -d@$RT +%Y%m%d%H%M`
RT_ISO=`date -u -d@$RT +%Y-%m-%dT%H:%M:%SZ`

if [ -d /smartmet ]; then
    BASE=/smartmet
else
    BASE=$HOME/smartmet
fi

OUT=$BASE/data/gfs/$AREA
CNF=$BASE/run/data/gfs/cnf
EDITOR=$BASE/editor/in
TMP=$BASE/tmp/data/gfs_${AREA}_${RESOLUTION}_${RT_DATE_HHMM}
LOGFILE=$BASE/logs/data/gfs_${AREA}_${RT_HOUR}.log

OUTNAME=${RT_DATE_HHMM}_gfs_$AREA

# Use log file if not run interactively
if [ $TERM = "dumb" ]; then
    exec &> $LOGFILE
fi

echo "Model Reference Time: $RT_ISO"
echo "Resolution: $RESOLUTION"
echo "Area: $AREA left:$LEFT right:$RIGHT top:$TOP bottom:$BOTTOM"
echo -n "Interval(s): "
for l in "${INTERVALS[@]}"
do
    echo -n "$l "
done
echo ""
echo "Temporary directory: $TMP"
echo "Output directory: $OUT"
echo "Output surface level file: ${OUTNAME}_surface.sqd"
echo "Output pressure level file: ${OUTNAME}_pressure.sqd"


if [ -z "$DRYRUN" ]; then
    mkdir -p $TMP/grb
    mkdir -p $OUT/{surface,pressure}/querydata
    mkdir -p $EDITOR
fi

function log {
    echo "$(date -u +%H:%M:%S) $1"
}

function runBacground()
{
    downloadStep $1 &
    ((dnum=dnum+1))
    if [ $(($dnum % 6)) == 0 ]; then
        wait
    fi
}

function testFile()
{
    if [ -s $1 ]; then
    # check return value, break if successful (0)
        grib_count $1 &>/dev/null
        if [ $? = 0 ] && [ $(grib_count $1) -gt 0 ]; then
            return 0
        else
            rm -f $1
            return 1
        fi
    else
        return 1
    fi
}

function downloadStep()
{
    STEPSTARTTIME=$(date +%s)
    step=$(printf '%03d' $1)

    if [ "$RESOLUTION" == "0p50" ]; then
        FILE="gfs.t${RT_HOUR}z.pgrb2full.${RESOLUTION}.f${step}"
    else
        FILE="gfs.t${RT_HOUR}z.pgrb2.${RESOLUTION}.f${step}"    
    fi

    if $(testFile ${TMP}/grb/${FILE}); then
        log "Cached file: $FILE size: $(stat --printf="%s" ${TMP}/grb/${FILE}) messages: $(grib_count ${TMP}/grb/${FILE})"
        break;
    else
        while [ 1 ]; do
            ((count=count+1))
            log "Downloading file: $FILE try: $count" 

            STARTTIME=$(date +%s)
            if [ -n "$WRF_COPY_DEST" ]; then
                curl -s -S -o $TMP/grb/${FILE} "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_${RESOLUTION}.pl?file=${FILE}&lev_1_mb=on&lev_2_mb=on&lev_3_mb=on&lev_5_mb=on&lev_7_mb=on&lev_10_mb=on&lev_15_mb=on&lev_20_mb=on&lev_30_mb=on&lev_40_mb=on&lev_50_mb=on&lev_70_mb=on&lev_100_mb=on&lev_150_mb=on&lev_200_mb=on&lev_250_mb=on&lev_300_mb=on&lev_350_mb=on&lev_400_mb=on&lev_450_mb=on&lev_500_mb=on&lev_550_mb=on&lev_600_mb=on&lev_650_mb=on&lev_700_mb=on&lev_750_mb=on&lev_800_mb=on&lev_850_mb=on&lev_900_mb=on&lev_925_mb=on&lev_950_mb=on&lev_975_mb=on&lev_1000_mb=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&lev_mean_sea_level=on&lev_entire_atmosphere=on&lev_entire_atmosphere_%5C%28considered_as_a_single_layer%5C%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_convective_cloud_layer=on&lev_0-0.1_m_below_ground=on&lev_0.1-0.4_m_below_ground=on&lev_0.4-1_m_below_ground=on&lev_1-2_m_below_ground=on&lev_1000_mb=on&lev_tropopause=on&lev_max_wind=on&lev_80_m_above_ground=on&var_CAPE=on&var_CIN=on&var_GUST=on&var_HGT=on&var_ICEC=on&var_LAND=on&var_PEVPR=on&var_PRATE=on&var_PRES=on&var_PRMSL=on&var_PWAT=on&var_RH=on&var_SHTFL=on&var_SNOD=on&var_SOILW=on&var_TSOIL=on&var_MSLET=on&var_SPFH=on&var_TCDC=on&var_TMP=on&var_DPT=on&var_UGRD=on&var_VGRD=on&var_DZDT=on&var_CNWAT=on&var_WEASD=on&subregion=&leftlon=${LEFT}&rightlon=${RIGHT}&toplat=${TOP}&bottomlat=${BOTTOM}&dir=%2Fgfs.${RT_DATE}%2F${RT_HOUR}%2Fatmos"
            else
                curl -s -S -o $TMP/grb/${FILE} "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_${RESOLUTION}.pl?file=${FILE}&lev_100_mb=on&lev_150_mb=on&lev_200_mb=on&lev_250_mb=on&lev_300_mb=on&lev_350_mb=on&lev_400_mb=on&lev_450_mb=on&lev_500_mb=on&lev_550_mb=on&lev_600_mb=on&lev_650_mb=on&lev_700_mb=on&lev_750_mb=on&lev_800_mb=on&lev_850_mb=on&lev_900_mb=on&lev_925_mb=on&lev_950_mb=on&lev_975_mb=on&lev_1000_mb=on&lev_surface=on&lev_2_m_above_ground=on&lev_10_m_above_ground=on&lev_mean_sea_level=on&lev_entire_atmosphere=on&lev_entire_atmosphere_%5C%28considered_as_a_single_layer%5C%29=on&lev_low_cloud_layer=on&lev_middle_cloud_layer=on&lev_high_cloud_layer=on&lev_convective_cloud_layer=on&var_CAPE=on&var_CIN=on&var_GUST=on&var_HGT=on&var_ICEC=on&var_LAND=on&var_PEVPR=on&var_PRATE=on&var_PRES=on&var_PRMSL=on&var_PWAT=on&var_RH=on&var_SHTFL=on&var_SNOD=on&var_SOILW=on&var_SPFH=on&var_TCDC=on&var_TMP=on&var_DPT=on&var_UGRD=on&var_VGRD=on&var_DZDT=on&subregion=&leftlon=${LEFT}&rightlon=${RIGHT}&toplat=${TOP}&bottomlat=${BOTTOM}&dir=%2Fgfs.${RT_DATE}%2F${RT_HOUR}%2Fatmos"
            fi
            ENDTIME=$(date +%s)
            if $(testFile ${TMP}/grb/${FILE}); then
                log "Downloaded file: $FILE size: $(stat --printf="%s" ${TMP}/grb/${FILE}) messages: $(grib_count ${TMP}/grb/${FILE}) time: $(($ENDTIME - $STARTTIME))s wait: $((($ENDTIME - $STEPSTARTTIME) - ($ENDTIME - $STEPSTARTTIME)))s"
                if [ -n "$GRIB_COPY_DEST" ]; then
                    rsync -ra ${TMP}/grb/${FILE} $GRIB_COPY_DEST/$RT_DATE_HH/
                fi

                if [ -n "$WRF_COPY_DEST" ]; then
                    # Check if RT_HOUR is in the array of valid hours
                    if [[ ${RT_HOUR} =~ ${VALID_HOURS} ]]; then
                        rsync -ra ${TMP}/grb/${FILE} $WRF_COPY_DEST/$RT_DATE_HH/
                    fi
                fi

#               if [ -n "$WRF_COPY_DEST" ]; then
#                   rsync -ra ${TMP}/grb/${FILE} $WRF_COPY_DEST/
#               fi
                break;
            fi

            # break if max count
            if [ $count = 60 ]; then break; fi; 
            sleep 60
        done # while 1

    fi
}

# Download intervals 
for l in "${INTERVALS[@]}"
do
    log "Downloading interval $l"
    for i in $(seq $l)
    do
        if [ -n "$DRYRUN" ]; then
            echo -n "$i "
        else
            runBacground $i
        fi
    done
    if [ -n "$DRYRUN" ]; then
        echo ""
    fi
done

if [ -n "$DRYRUN" ]; then
    exit
fi

# Wait for the downloads to finish
wait

if [ -n "$GRIB_COPY_DEST" ]; then
    ls -1 $TMP/grb/ > $TMP/${RT_DATE_HH}.txt
    rsync -a $TMP/${RT_DATE_HH}.txt $GRIB_COPY_DEST/
fi

log ""
log "Download size $(du -hs $TMP/grb/|cut -f1) and $(ls -1 $TMP/grb/|wc -l) files."

# log "Converting surface grib files to qd files..."
# gribtoqd -d -t -L 1   -p "54,GFS Surface"  -c $CNF/gfs-gribtoqd.cnf -o $TMP/${OUTNAME}_surface.sqd  $TMP/grb/
# log "Converting pressure grib files to qd files..."
# gribtoqd -d -t -L 100 -p "54,GFS Pressure" -c $CNF/gfs-gribtoqd.cnf -o $TMP/${OUTNAME}_pressure.sqd $TMP/grb/
# #mv -f $TMP/$OUTNAME.sqd_levelType_1 $TMP/${OUTNAME}_surface.sqd
# #mv -f $TMP/$OUTNAME.sqd_levelType_100 $TMP/${OUTNAME}_pressure.sqd

# #
# # Post process some parameters 
# #
# log "Post processing ${OUTNAME}_pressure.sqd"
# cp -f  $TMP/${OUTNAME}_pressure.sqd $TMP/${OUTNAME}_pressure.sqd.tmp
# log "Post processing ${OUTNAME}_surface.sqd"
# qdscript $CNF/gfs-surface.st < $TMP/${OUTNAME}_surface.sqd > $TMP/${OUTNAME}_surface.sqd.tmp

# #
# # Create querydata totalWind and WeatherAndCloudiness objects
# #
# log "Creating Wind and Weather objects: ${OUTNAME}_pressure.sqd"
# qdversionchange -w 0 7 < $TMP/${OUTNAME}_pressure.sqd.tmp > $TMP/${OUTNAME}_pressure.sqd
# log "Creating Wind and Weather objects: ${OUTNAME}_surface.sqd"
# qdversionchange -a 7 < $TMP/${OUTNAME}_surface.sqd.tmp > $TMP/${OUTNAME}_surface.sqd

# #
# # Copy files to SmartMet Workstation and SmartMet Production directories
# #
# # Pressure level
# if [ -s $TMP/${OUTNAME}_pressure.sqd ]; then
#     log "Testing ${OUTNAME}_pressure.sqd"
#     if qdstat $TMP/${OUTNAME}_pressure.sqd; then
#         log  "Compressing ${OUTNAME}_pressure.sqd"
#         lbzip2 -k $TMP/${OUTNAME}_pressure.sqd
#         log "Moving ${OUTNAME}_pressure.sqd to $OUT/pressure/querydata/"
#         mv -f $TMP/${OUTNAME}_pressure.sqd $OUT/pressure/querydata/
#         log "Moving ${OUTNAME}_pressure.sqd.bz2 to $EDITOR/"
#         mv -f $TMP/${OUTNAME}_pressure.sqd.bz2 $EDITOR/
#     else
#         log "File $TMP/${OUTNAME}_pressure.sqd is not valid qd file."
#     fi
# fi

# # Surface
# if [ -s $TMP/${OUTNAME}_surface.sqd ]; then
#     log "Testing ${OUTNAME}_surface.sqd"
#     if qdstat $TMP/${OUTNAME}_surface.sqd; then
#         log "Compressing ${OUTNAME}_surface.sqd"
#         lbzip2 -k $TMP/${OUTNAME}_surface.sqd
#         log "Moving ${OUTNAME}_surface.sqd to $OUT/surface/querydata/"
#         mv -f $TMP/${OUTNAME}_surface.sqd $OUT/surface/querydata/
#         log "Moving ${OUTNAME}_surface.sqd.bz2 to $EDITOR"
#         mv -f $TMP/${OUTNAME}_surface.sqd.bz2 $EDITOR/
#     else
#         log "File $TMP/${OUTNAME}_surface.sqd is not valid qd file."
#     fi
# fi

rm -f $TMP/*_gfs_*
rm -f $TMP/*.txt
rm -f $TMP/grb/gfs*
rmdir $TMP/grb
rmdir $TMP
