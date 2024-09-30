#!/bin/bash 
#This is for automatic running of WRF
#07 Feb 2020

year=$1;month=$2;day=$3;hour=$4;leadtime=$5 prod_dir=$6
interval=3;

echo $year

wps_dir="/home/wrf/WPS"
wrf_dir="/home/wrf/WRF"
run_dir="${prod_dir}/${year}${month}${day}${hour}"

s_date="$year-$month-$day ${hour}:00:00"
eyear=$(date -d "$s_date $leadtime hours" "+%Y")
emonth=$(date -d "$s_date $leadtime hours" "+%m")
eday=$(date -d "$s_date $leadtime hours" "+%d")
ehour=$(date -d "$s_date $leadtime hours" -u "+%H")

cd ${run_dir} 
###########################Check ICBC


if [ -f ${run_dir}/met_em.d02.${eyear}-${emonth}-${eday}_${ehour}:00:00.nc ];then
  echo "Ready to set up WRF" > wrf.log
else
  echo "Not enough ICBC files" > wrf.log
  exit 1
fi

#3. Running WRF simulations


#3.1 link necessary files
ln -sf ${wrf_dir}/main/*.exe .
ln -sf ${wrf_dir}/run/gribmap.txt . 
ln -sf ${wrf_dir}/run/RRTM* .
ln -sf ${wrf_dir}/run/*TBL .
ln -sf ${wrf_dir}/run/*tbl .
ln -sf ${wrf_dir}/run/ozone* .
ln -sf ${wrf_dir}/run/CAMtr* .
#ln -sf /fmi/projappl/project_2002463/scripts/extra_io_fields.txt .
#cp ${main_dir}/met_em* .

echo "link necessary files finished" >> wrf.log 

#3.2 edit namlist.input
#rm  ${run_dir}/namelist.input

run_days=$((leadtime/24))
cat << AAA > namelist.input
&time_control
 run_days                            = ${run_days},
 run_hours                           = 0,
 run_minutes                         = 0,
 run_seconds                         = 0,
 start_year                          = $year, $year, 2017,
 start_month                         = $month, $month,   01,
 start_day                           = $day, $day,   24,
 start_hour                          = $hour, $hour,   12,
 end_year                            = $eyear, $eyear, 2000,
 end_month                           = $emonth, $emonth,   01,
 end_day                             = $eday, $eday,   25,
 end_hour                            = $ehour, $ehour,   12,
 interval_seconds                    = 10800
 input_from_file                     = .true.,.true.,.true.,
 history_interval                    = 60, 60,
 frames_per_outfile         = 1, 1,
 restart                    = .false.,
 restart_interval           = 14400,
 io_form_history            = 2
 io_form_auxinput4          = 2
 auxinput4_interval         = 360
 auxinput4_inname           = "wrflowinp_d<domain>"
 io_form_input              = 2
 io_form_restart            = 2
 io_form_boundary           = 2
 debug_level                = 0
 use_netcdf_classic         = T
 /

&domains
 time_step                  = 45
 time_step_fract_num        = 0
 time_step_fract_den        = 1
 time_step_dfi              = 15
 max_dom                    = 2
 s_we                       = 1, 1
 e_we                       = 300,289,                                                                                                                       e_sn                       = 200,187,                       
 s_vert                     = 1, 1
 e_vert                     = 45, 45
 num_metgrid_levels         = 34,
 num_metgrid_soil_levels    = 4,
 dx                         = 9000.0000, 3000.0000
 dy                         = 9000.0000, 3000.0000
 grid_id                    = 1, 2
 parent_id                  = 0, 1
 i_parent_start             = 1, 63,
 j_parent_start             = 1, 42,
 parent_grid_ratio          = 1, 3
 parent_time_step_ratio     = 1, 3
 feedback                   = 1
 smooth_option              = 0
 /


&physics
 mp_physics                          = 2,     2,     3,
 mp_zero_out                         = 0,
 mp_zero_out_thresh                  = 1.e-8
 mp_tend_lim                         = 10.
 no_mp_heating                       = 0,
 do_radar_ref                        = 1,
 shcu_physics                        = 0,
 topo_wind                           = 0,
 isfflx                              = 1,
 iz0tlnd                             = 1,
 isftcflx                            = 0,
 ra_lw_physics                       = 1,     1,     1,
 ra_sw_physics                       = 1,     1,     1,
 radt                                = 30,    30,    30,
 sf_sfclay_physics                   = 1,     1,     1,
 sf_surface_physics                  = 2,     2,     2,
 bl_pbl_physics                      = 1,     1,     1,
 bldt                                = 0,     0,     0,
 cu_physics                          = 1,     1,     0,
 cudt                                = 5,     5,     5,
 ifsnow                              = 1,
 icloud                              = 1,
 surface_input_source                = 3,
 num_soil_layers                     = 4,
 num_land_cat                        = 21,
 sf_urban_physics                    = 0,  
 sst_update                          = 1,
 tmn_update                          = 1,
 sst_skin                            = 1,
 kfeta_trigger                       = 1,
 mfshconv                            = 0,
 prec_acc_dt                         = 0,
 sf_lake_physics                     = 1,
 /

&noah_mp
/

&dynamics
 hybrid_opt                 = 2,
 etac                       = 0.175,  
 w_damping                  = 1,
 diff_opt                   = 1,      1,      1,
 km_opt                     = 4,      4,      4,
 diff_6th_opt               = 2,      2,      2,
 diff_6th_factor            = 0.12,   0.12,   0.12,
 base_temp                  = 290.
 damp_opt                   = 3,
 zdamp                      = 5000.,  5000.,  5000.,
 dampcoef                   = 0.2,    0.2,    0.2
 khdif                      = 0,      0,      0,
 kvdif                      = 0,      0,      0,
 non_hydrostatic            = .true., .true., .true.,
 moist_adv_opt              = 1,      1,      1,     
 scalar_adv_opt             = 1,      1,      1,     
 gwd_opt                    = 1,
/

&fdda
 grid_fdda                  = 0
/

&bdy_control
 spec_bdy_width             = 10
 spec_zone                  = 1
 relax_zone                 = 9
 spec_exp                   = 0.33,
 specified                  = T, F
 nested                     = F, T
/

&grib2
/

&namelist_quilt
 nio_tasks_per_group        = 0
 nio_groups                 = 1
/

&diags
 p_lev_diags                = 0
 z_lev_diags                = 0
/

AAA

#3.3 run REAL.exe
cat << BBB > run_real.bash
#!/bin/bash

cd ${run_dir}

time mpirun -np 10 real.exe

BBB
echo "Start to run REAL.exe" >> wrf.log
chmod +x run_real.bash
./run_real.bash 




echo "run REAL pass the test" >> wrf.log

#3.4 run WRF.exe
cat << CCC > run_wrf.bash
#!/bin/bash

cd ${run_dir}

date
time mpirun -np 40 wrf.exe
date
CCC


echo "Ready to run WRF.exe" >> wrf.log
chmod +x run_wrf.bash
./run_wrf.bash


if [ -f ${run_dir}/wrfout_d02_${eyear}-${emonth}-${eday}_${ehour}:00:00 ];then
  echo "WRF finished" > wrf.log
else
    echo Second try run wrf >> wrf.log
    ./run_wrf.bash
fi

echo "running WRF.exe finished" >> wrf.log


echo "Cycle" ${year}${month}${day}${hour}" WRF run finished" >> wrf.log


