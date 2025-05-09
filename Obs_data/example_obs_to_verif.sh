#!/bin/bash

station_url="https://wwcs.tj/observations/stations/"
data_url="https://wwcs.tj/observations/smartmet/?siteID="
station_file="/home/wrf/WRF_Model/Verification/Data/Static/stations.csv"
working_file="/home/wrf/WRF_Model/Verification/Data/Obs/obs_from_db.csv"
output_file="/home/wrf/WRF_Model/Verification/Data/Obs/obs_to_verif.csv"

echo "getting station data from db";
echo "SID,lat,lon,elev,name" > $station_file
curl -s $station_url | jq -r '.[] | [.latitude, .longitude, .altitude, .siteID] | @csv' | sed 's/"//g' | awk '{print NR "," $1 "," $2 "," $3 "," $4}' | sed 's/,\+$//' >> $station_file

rm -r $working_file
echo "Downloading site data for each station..."
tail -n +2 $station_file | while IFS=, read -r stationID latitude longitude altitude siteID; do
    echo "Processing siteID: $data_url$siteID"
    curl -s "${data_url}${siteID}" | jq -r --arg stationID "$stationID" '.[] |
        select((.datetime | strptime("%a, %d %b %Y %H:%M:%S %Z") | strftime("%M")) == "00") |
        [   $stationID,
            (.datetime | strptime("%a, %d %b %Y %H:%M:%S %Z") | strftime("%Y%m%d%H")),
            (.data[] | select(.machineName == "air_temperature") | .value // ""),
            (.data[] | select(.machineName == "relative_humidity") | .value // ""),
            (.data[] | select(.machineName == "air_pressure") | .value // ""),
            (.data[] | select(.machineName == "precipitation") | .value // ""),
            (.data[] | select(.machineName == "wind_direction") | .value // ""),
            (.data[] | select(.machineName == "wind_speed") | .value // "")
        ] | @csv' | sed 's/"//g' >> $working_file
done

# Delete old and create the new output file
rm -f $output_file

echo "valid_dttm,SID,lat,lon,elev,T2m,Td2m,Pressure,Pcp,Wdir,WS" > $output_file
# Combine the information from the two CSV files based on station_id
awk -F, '
    NR==FNR {stations[$1]=$2","$3","$4","$5; next}
    FNR>1 {
        valid_dttm=$2
        stationID=$1
        id=stations[stationID]
        if (id != "") {
            split(id, station_info, ",")
            print valid_dttm","stationID","station_info[1]","station_info[2]","station_info[3]","$3","$4","$5","$6","$7","$8
        }
    }
' $station_file $working_file >> $output_file
