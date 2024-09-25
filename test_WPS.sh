#!/bin/bash 

#This is for automatic running of WPS
#March 2024
#2. Create initial conditions WPS

year=$1;month=$2;day=$3;hour=$4;leadtime=$5 prod_dir=$6
interval=3 ; res="0p025" #resolution


data_dir="/home/wrf/GFS/"
wps_dir="/home/wrf/WPS/"
run_dir="${prod_dir}/${year}${month}${day}${hour}"


s_date="$year-$month-$day ${hour}:00:00"
eyear=$(date -d "$s_date $leadtime hours" "+%Y")
emonth=$(date -d "$s_date $leadtime hours" "+%m")
eday=$(date -d "$s_date $leadtime hours" "+%d")
ehour=$(date -d "$s_date $leadtime hours" -u "+%H")


mkdir -p $run_dir
cd ${run_dir}
echo "Created new rundir" $run_dir
 

#rm -rf Vtable GRIBFILE* *.log *.out run_WPS.bash GFS:* PFILE:* met_em*

#Create namelist for WPS
cat << AAA > namelist.wps 
&share
 wrf_core                   = 'ARW'
 max_dom                    = 2
 start_date                 = '${year}-${month}-${day}_${hour}:00:00','${year}-${month}-${day}_${hour}:00:00'
 end_date                   = '${eyear}-${emonth}-${eday}_${ehour}:00:00','${eyear}-${emonth}-${eday}_${ehour}:00:00'
 active_grid                = .true., .true.
 interval_seconds           = 10800
 io_form_geogrid            = 2
/

&geogrid
 parent_id         = 1,1,
 parent_grid_ratio = 1,3,
 i_parent_start    = 1,63,
 j_parent_start    = 1,42,
 e_we          = 300,289,
 e_sn          = 200,187,
 geog_data_res = 'modis_lakes+modis_30s+5m','modis_lakes+modis_30s+30s',
 dx = 9000,
 dy = 9000,
 map_proj =  'mercator',
 ref_lat   = -0.035,
 ref_lon   = 33.401,
 truelat1  = -0.035,
 truelat2  = 0,
 stand_lon = 33.401,
 geog_data_path = '/home/wrf/Data/geog/',
 opt_geogrid_tbl_path = '/home/wrf/WPS/geogrid/',
 ref_x = 150.0,
 ref_y = 100.0,
/


&ungrib
 out_format                 = 'WPS'
 prefix                     = 'GFS'
/

&metgrid
 fg_name = 'GFS'
 io_form_metgrid = 2,
 constants_name = /home/wrf/Data/tables/aerosol/QNWFA_QNIFA_SIGMA_MONTHLY.dat
/
AAA

#Run exe files
Vtable_dir="/home/wrf/WPS/ungrib/Variable_Tables"
ln -sf ${Vtable_dir}/Vtable.GFS Vtable
echo "link Vtable finish" >> wps.log

echo "Start running exe files" >> wps.log

cat << BBB > run_geogrid.bash
#!/bin/bash
export WRF_EM_CORE=1
export NETCDF=/home/wrf/libs/netcdf-c-4.9.2/install_dir/lib
export NETCDF4=1
export HDF5=/home/wrf/libs/hdf5-1.14.3/install_dir
export jasper=/home/wrf/libs/jasper-1.900.1/install_dir
export JASPERLIB=/home/wrf/libs/jasper-1.900.1/install_dir/lib
export JASPERINC=/home/wrf/libs/jasper-1.900.1/install_dir/include
export WRF_DA_CORE=0
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export WRF_DIR=/home/wrf/WRF

cd ${run_dir}

pwd >>wps.log
date
mpirun -np 1 ${wps_dir}geogrid.exe
date

BBB

chmod +x run_geogrid.bash
./run_geogrid.bash

until [ -f geo_em.d02.nc ];do
  sleep 5 >> wps.log
done
sleep 5
echo "running GEOGRID.exe finished" >> wps.log

cd $run_dir

${wps_dir}./link_grib.csh ${data_dir}/${year}${month}${day}${hour}/gfs*
#
echo "Link grid file finished" >> wps.log

cat << CCC > run_ungrib.bash
#!/bin/bash
export WRF_EM_CORE=1
export NETCDF=/home/wrf/libs/netcdf-c-4.9.2/install_dir/lib
export NETCDF4=1
export HDF5=/home/wrf/libs/hdf5-1.14.3/install_dir
export jasper=/home/wrf/libs/jasper-1.900.1/install_dir
export JASPERLIB=/home/wrf/libs/jasper-1.900.1/install_dir/lib
export JASPERINC=/home/wrf/libs/jasper-1.900.1/install_dir/include
export WRF_DA_CORE=0
export WRFIO_NCD_LARGE_FILE_SUPPORT=1
export WRF_DIR=/home/wrf/WRF

cd ${run_dir}

pwd >>wps.log
date
mpirun -np 1 ${wps_dir}ungrib.exe
date

CCC
 
chmod +x run_ungrib.bash
./run_ungrib.bash

until [ -f GFS\:${eyear}-${emonth}-${eday}_${ehour} ];do
  sleep 5 >> wps.log
done
sleep 5
echo "running UNGRIB.exe finished" >> wps.log



#ln -sf ${wps_dir}util/ecmwf_coeffs ecmwf_coeffs
#echo "linked  ecmwf model field coefficents table" >> wps.log
#${wps_dir}util/./calc_ecmwf_p.exe &>ecmwf_coeffs.log 

#echo "calculated ecmwf model field coefficents" >> wps.log

metgrid_dir="/home/wrf/WPS/metgrid/"

ln -sf ${metgrid_dir} metgrid


cat << DDD > run_metgrid.bash
#!/bin/bash

cd ${run_dir}

date
time mpirun -np 24 ${wps_dir}metgrid.exe  
date

DDD
 
chmod +x run_metgrid.bash
./run_metgrid.bash


until [ -f met_em.d02.${eyear}-${emonth}-${eday}_${hour}:00:00.nc ]
do
    echo "Not enough yet ICBC files" >> wps.log
    sleep 60 
done
sleep 30


echo "running METGRID.exe finished" >> wps.log 


if [ -f ${run_dir}/met_em.d02.${eyear}-${emonth}-${eday}_${hour}:00:00.nc ];then
  echo "Ready to set up WRF" >> wrf.log
else
echo "Something went wrong, check log-files" >> wps.log 
exit 1
fi

echo "Creating ICBC for WRF finally done. Good job !!!" >> wps.log
