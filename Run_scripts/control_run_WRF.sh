#!/bin/bash

#For WRF run control
###If there is one control running then exit: in progress

anhour=$1
hour=$anhour

#1.for daily running
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

#year=`date "+%Y"`; month=`date "+%m"`;day=`date "+%d"`; hour=$anhour

leadtime=120  #lengt of the forecast
main_dir="/home/wrf/scripts"
prod_dir="/home/wrf/out"
data_dir="/home/wrf/GFS"
verification_dir="/home/wrf/Verification/Scripts"
cd ${main_dir}


	  echo "*************" > ${main_dir}/logs/main.log
	  echo $year$month$day$hour "WRF Run started "  >> ${main_dir}/logs/main.log
	  date  >> ${main_dir}/logs/main.log 
#       #1. Download data

	  gribnum=42
	  files_found=false

	  echo "1) Let's check the boundary files exists  before ems_prep: " >> /home/wrf/scripts/logs/main.log
	  echo "   "`date +"%H:%M %Y%m%d"` >> /home/wrf/scripts/logs/main.log
	  for ((i=1; i<=15; i++)); do
	      # Count the number of files in the directory with the specified naming pattern
	      file_count=$(find $data_dir"/"$year$month$day$hour -maxdepth 1 -type f -name "gfs.t${anhour}z.pgrb2.0p25.f*" | wc -l)
	      echo $file_count
	     

	      # Check if the file count meets the expected count           
	      if [ "$file_count" -ge "$gribnum" ]; then
		  echo "There are at least $gribnum files in the directory. Continuing execution." >> /home/wrf/scripts/logs/main.log
		  files_found=true
		  break
	      else
		  sleep 300  # Wait for the retry interval
	      fi
	  done

	  # If enough files are not found after all retries, exit with an error message
	  if [ "$files_found" = false ]; then
	      echo "Exceeded maximum retries. Not enough boundary files in the directory. Terminating the run!" >> /home/wrf/scripts/logs/main.log
	      echo "   "`date +"%H:%M %Y%m%d"` >> /home/wrf/scripts/logs/main.log
	      exit 1  # Exit with an error code
	  fi

	  #       ./download_gfs.sh $year $month $day $hour $leadtime 
	  #2.WPS
	  ./run_WPS.sh $year $month $day $hour $leadtime $prod_dir 
	  echo "WPS finished">> ${main_dir}/logs/main.log 
	  date >>  ${main_dir}/logs/main.log 
	  #3.WRF
	  ./run_WRF.sh $year $month $day $hour $leadtime $prod_dir
	  echo $year$month$day$hour "Run finished"  >> ${main_dir}/logs/main.log 
	  date >> ${main_dir}/logs/main.log 
	  tail -2  ${prod_dir}/$year$month$day$hour/rsl.out.0000 | head -1 >> ${main_dir}/logs/main.log

	  #Go to Verification directory  and read from model output to SQlite-files in selected observation points.
          
	  #cd $verification_dir
          #./verification.sh $year $month $day $hour

	  
	  echo "NetCDF to Grib conversion with UPP"
          /home/wrf/scripts/execute_upp $hour

	  #echo "Copy files to SmartMet"
	  #rsync -e ssh -av --include='*/' --include="*d01*" --exclude="*" /home/wrf/UPP_out/$year$month$day$hour smartmet@10.10.233.145:/smartmet/data/incoming/wrf/d01/
	  #rsync -e ssh -av --include='*/' --include="*d02*" --exclude="*" /home/wrf/UPP_out/$year$month$day$hour smartmet@10.10.233.145:/smartmet/data/incoming/wrf/d02/
          #ssh smartmet@10.10.233.145 /smartmet/run/data/wrf/bin/wrf.sh $hour d01 
	  #ssh smartmet@10.10.233.145 /smartmet/run/data/wrf/bin/wrf.sh $hour d02 	

          echo "FINISHED !! WE ARE FREE NOW !! YEAH"

#   done
#  done
#done
