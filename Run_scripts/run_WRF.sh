#!/bin/bash

# ===============================================
# WRF Model Automation Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

#Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# Script inputs
year=$1;month=$2;day=$3;hour=$4;leadtime=$5 prod_dir=$6


# Directories and paths
run_dir="${BASE_DIR}/${prod_dir}/${year}${month}${day}${hour}"

# Calculate end date and time
s_date="$year-$month-$day ${hour}:00:00"
eyear=$(date -d "$s_date $leadtime hours" "+%Y")
emonth=$(date -d "$s_date $leadtime hours" "+%m")
eday=$(date -d "$s_date $leadtime hours" "+%d")
ehour=$(date -d "$s_date $leadtime hours" -u "+%H")


# Check initial and boundary conditions
cd ${run_dir}
if [ -f ${run_dir}/met_em.d02.${eyear}-${emonth}-${eday}_${ehour}:00:00.nc ];then
  echo "Ready to set up WRF" 
else
  echo "Not enough ICBC files"
  exit 1
fi

# Link required files for WRF run
ln -sf ${WRF_DIR}/main/*.exe .
ln -sf $WRF_DIR/run/{gribmap.txt,RRTM*,*TBL,*tbl,ozone*,CAMtr*} .
echo "Linked necessary files"

# Configure `namelist.input` for WRF run
run_days=$((leadtime/24))
cat << EOF > namelist.input
&time_control
 run_days                   = ${run_days},
 run_hours                  = 0,
 run_minutes                = 0,
 run_seconds                = 0,
 start_year                 = $year, $year, 2017,
 start_month                = $month, $month,   01,
 start_day                  = $day, $day,   24,
 start_hour                 = $hour, $hour,   12,
 end_year                   = $eyear, $eyear, 2000,
 end_month                  = $emonth, $emonth,   01,
 end_day                    = $eday, $eday,   25,
 end_hour                   = $ehour, $ehour,   12,
 interval_seconds           = 10800
 input_from_file            = .true.,.true.,.true.,
 history_interval           = 60, 60,
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
 time_step                  = 30
 time_step_fract_num        = 0
 time_step_fract_den        = 1
 time_step_dfi              = 15
 max_dom                    = 2
 s_we                       = 1, 1
 e_we                       = 103,286,                                                                                                                       
 e_sn                       = 195,186,
 s_vert                     = 1, 1
 e_vert                     = 45, 45
 num_metgrid_levels         = 34,
 num_metgrid_soil_levels    = 4,
 dx                         = 7000.0000, 1400.0000
 dy                         = 7000.0000, 1400.0000
 grid_id                    = 1, 2
 parent_id                  = 0, 1
 i_parent_start             = 1, 21,
 j_parent_start             = 1, 18,
 parent_grid_ratio          = 1, 5
 parent_time_step_ratio     = 1, 3
 feedback                   = 1
 smooth_option              = 0
 /


&physics
 mp_physics                 = 2,     2,     3,
 mp_zero_out                = 0,
 mp_zero_out_thresh         = 1.e-8
 mp_tend_lim                = 10.
 no_mp_heating              = 0,
 do_radar_ref               = 1,
 shcu_physics               = 0,
 topo_wind                  = 0,
 isfflx                     = 1,
 iz0tlnd                    = 1,
 isftcflx                   = 0,
 ra_lw_physics              = 1,     1,     1,
 ra_sw_physics              = 1,     1,     1,
 radt                       = 30,    30,    30,
 sf_sfclay_physics          = 1,     1,     1,
 sf_surface_physics         = 2,     2,     2,
 bl_pbl_physics             = 1,     1,     1,
 bldt                       = 0,     0,     0,
 cu_physics                 = 1,     1,     0,
 cudt                       = 5,     5,     5,
 ifsnow                     = 1,
 icloud                     = 1,
 surface_input_source       = 3,
 num_soil_layers            = 4,
 num_land_cat               = 21,
 sf_urban_physics           = 0,
 sst_update                 = 1,
 tmn_update                 = 1,
 sst_skin                   = 1,
 kfeta_trigger              = 1,
 mfshconv                   = 0,
 prec_acc_dt                = 0,
 sf_lake_physics            = 1,
 use_lakedepth 		          = 0,
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
/ob_window_min

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
EOF

# ===============================================
# Step 1: Run `real.exe` for initialization
# ===============================================

echo "Running real.exe..."
time mpirun -np 10 ${run_dir}/real.exe
echo "Real.exe completed."

# ===============================================
# Step 2: Data assimilation (optional, WRFDA variable true/false)
# ===============================================
if $WRFDA; then
  cd $run_dir
  ./run_WRFDA.sh $year $month $day $hour $leadtime $prod_dir
else
  echo "Running model without data assimilation"
fi

# ===============================================
# Step 3: Run WRF model
# ===============================================

echo "Ready to run WRF.exe"
cd $run_dir
time mpirun -np 40 ./wrf.exe
if [ ! -f "${run_dir}/wrfout_d02_${eyear}-${emonth}-${eday}_${ehour}:00:00" ]; then
  echo "Error: WRF failed."
  exit 1
fi
echo "WRF finished"

# ===============================================
# Step 4: Copy files for next cycle (with DA only)
# ===============================================
if $WRFDA; then
  echo "Copying fg and VARBC files"
  #First guess files
  fg_date=$(date -d "$s_date $INTERVAL hours" "+%Y-%m-%d %H:%M:%S")
  read fgyear fgmonth fgday fghour fgmin fgsec <<< $(echo $fg_date | tr '-' ' ' | tr ':' ' ')
  cp $run_dir/wrfout_d01_${fgyear}-${fgmonth}-${fgday}_${fghour}:00:00 $DAT_DIR/rc/ || :
  cp $run_dir/wrfout_d02_${fgyear}-${fgmonth}-${fgday}_${fghour}:00:00 $DAT_DIR/rc/ || :
  #VARBC file
  cp $WORK_DIR_DA/VARBC.out $DAT_DIR/varbc/ || :
fi

echo "Cycle" ${year}${month}${day}${hour}" WRF run finished"


