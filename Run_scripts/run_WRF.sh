#!/bin/bash

# ===============================================
# WRF Model Automation Script
# Author: Mikael Hasu, Janne Kauhanen
# Date: November 2024
# ===============================================

#Load environment
source /home/wrf/WRF_Model/scripts/env.sh

# Script inputs
year=$1;month=$2;day=$3;hour=$4;leadtime=$5

# Directories and paths
run_dir="${PROD_DIR}/${year}${month}${day}${hour}"

# Calculate end date and time
s_date="$year-$month-$day ${hour}:00:00"
eyear=$(date -d "$s_date $leadtime hours" "+%Y")
emonth=$(date -d "$s_date $leadtime hours" "+%m")
eday=$(date -d "$s_date $leadtime hours" "+%d")
ehour=$(date -d "$s_date $leadtime hours" -u "+%H")

# ===============================================
# Read domain settings from domain.txt
# ===============================================
DOMAIN_FILE="${MAIN_DIR}/domain.txt"

if [ ! -f "$DOMAIN_FILE" ]; then
  echo "Error: domain.txt not found at $DOMAIN_FILE"
  echo "Please save your WRF Domain Wizard namelist.wps file as domain.txt in the scripts directory"
  exit 1
fi

echo "Reading domain configuration from $DOMAIN_FILE"

# Parse the domain.txt file using Python script
eval $(${MAIN_DIR}/parse_namelist_wps.py $DOMAIN_FILE)

# Calculate dx/dy for inner domains based on parent_grid_ratio
DX_VALUES=()
DY_VALUES=()

# d01 (outer domain)
DX_VALUES+=($DX)
DY_VALUES+=($DY)

ratio=${PARENT_GRID_RATIO[1]}
inner_dx=$(echo "$DX / $ratio" | bc -l | xargs printf "%.4f")
inner_dy=$(echo "$DY / $ratio" | bc -l | xargs printf "%.4f")
DX_VALUES+=($inner_dx)
DY_VALUES+=($inner_dy)


# ===============================================
# Dynamic CPU decomposition calculation
# ===============================================
# Goal: Find optimal nproc_x and nproc_y such that:
# 1. nproc_x * nproc_y <= MAX_CPU
# 2. Each tile has at least 10 grid points per direction (WRF minimum patch size)

calculate_nproc() {
    local grid_x_d01=$1 grid_y_d01=$2 grid_x_d02=$3 grid_y_d02=$4 max_cpu=$5
    local min_tile=10
    
    # Calculate maximum processors (most restrictive domain constraint)
    local max_nx=$(( (grid_x_d01/min_tile < grid_x_d02/min_tile ? grid_x_d01/min_tile : grid_x_d02/min_tile) ))
    local max_ny=$(( (grid_y_d01/min_tile < grid_y_d02/min_tile ? grid_y_d01/min_tile : grid_y_d02/min_tile) ))
    [[ $max_nx -lt 1 ]] && max_nx=1
    [[ $max_ny -lt 1 ]] && max_ny=1
    
    local best_nx=1 best_ny=1 best_score=999999
    
    # Find best decomposition maximizing CPU usage while maintaining aspect ratio
    for nx in $(seq 1 $max_nx); do
        for ny in $(seq 1 $max_ny); do
            local total=$((nx * ny))
            [[ $total -gt $max_cpu ]] && continue
            
            # Verify both domains meet minimum tile size
            [[ $((grid_x_d01/nx)) -lt $min_tile || $((grid_y_d01/ny)) -lt $min_tile || \
               $((grid_x_d02/nx)) -lt $min_tile || $((grid_y_d02/ny)) -lt $min_tile ]] && continue
            
            # Score: aspect ratio diff + CPU underutilization penalty
            local score=$(echo "scale=4; sqrt((($grid_x_d02/$nx)/($grid_y_d02/$ny) - $grid_x_d02/$grid_y_d02)^2) + (1 - $total/$max_cpu)" | bc)
            
            [[ $(echo "$score < $best_score" | bc) -eq 1 ]] && { best_score=$score; best_nx=$nx; best_ny=$ny; }
        done
    done
    
    echo "$best_nx $best_ny"
}

# Get domain dimensions
GRID_X_D01=${E_WE[0]}
GRID_Y_D01=${E_SN[0]}
GRID_X_D02=${E_WE[1]}
GRID_Y_D02=${E_SN[1]}

# Calculate optimal decomposition considering both domains
read NPROC_X NPROC_Y <<< $(calculate_nproc $GRID_X_D01 $GRID_Y_D01 $GRID_X_D02 $GRID_Y_D02 $MAX_CPU)

# Calculate optimal CPUs to use
OPTIMAL_CPUS=$((NPROC_X * NPROC_Y))

echo "Domain Configuration:"
echo "  Domain 1: ${E_WE[0]} x ${E_SN[0]} grid points"
echo "  Domain 2: ${E_WE[1]} x ${E_SN[1]} grid points"
echo "MPI Decomposition:"
echo "  nproc_x = $NPROC_X, nproc_y = $NPROC_Y"
echo "  Total CPUs = $OPTIMAL_CPUS (max available: $MAX_CPU)"
echo "  D01 tile size: ~$((GRID_X_D01 / NPROC_X)) x $((GRID_Y_D01 / NPROC_Y)) points"
echo "  D02 tile size: ~$((GRID_X_D02 / NPROC_X)) x $((GRID_Y_D02 / NPROC_Y)) points"

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

# Helper function to format bash arrays as comma-separated lists for namelist
format_array() {
    local arr=("$@")
    local result
    printf -v result "%s, " "${arr[@]}"
    echo "${result%, }"
}

# Configure `namelist.input` for WRF run
run_days=$((leadtime/24))
run_hours=$((leadtime%24))
cat << EOF > namelist.input
&time_control
 run_days                   = ${run_days},
 run_hours                  = ${run_hours},
 run_minutes                = 0,
 run_seconds                = 0,
 start_year                 = $year, $year,
 start_month                = $month, $month,
 start_day                  = $day, $day,
 start_hour                 = $hour, $hour,
 end_year                   = $eyear, $eyear,
 end_month                  = $emonth, $emonth,
 end_day                    = $eday, $eday,
 end_hour                   = $ehour, $ehour,
 interval_seconds           = 10800
 input_from_file            = .true., .true.,
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
 time_step                  = 45
 time_step_fract_num        = 0
 time_step_fract_den        = 1
 max_dom                    = 2
 s_we                       = 1, 1
 e_we                       = $(format_array "${E_WE[@]}")
 e_sn                       = $(format_array "${E_SN[@]}")
 s_vert                     = 1, 1
 e_vert                     = 45, 45
 num_metgrid_levels         = 34,
 num_metgrid_soil_levels    = 4,
 dx                         = $(format_array "${DX_VALUES[@]}")
 dy                         = $(format_array "${DY_VALUES[@]}")
 grid_id                    = 1, 2
 parent_id                  = $(format_array "${PARENT_ID[@]}")
 i_parent_start             = $(format_array "${I_PARENT_START[@]}")
 j_parent_start             = $(format_array "${J_PARENT_START[@]}")
 parent_grid_ratio          = $(format_array "${PARENT_GRID_RATIO[@]}")
 parent_time_step_ratio     = 1, 3
 feedback                   = 1
 smooth_option              = 0
 nproc_x                    = $NPROC_X
 nproc_y                    = $NPROC_Y
 smooth_cg_topo             = .true.
 /


&physics
 mp_physics                 = 8,     8,
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
 ra_lw_physics              = 4,     4,
 ra_sw_physics              = 4,     4,
 radt                       = 10,    10,
 sf_sfclay_physics          = 1,     1,
 sf_surface_physics         = 2,     2,
 bl_pbl_physics             = 1,     1,
 bldt                       = 0,     0,
 cu_physics                 = 1,     0,
 cudt                       = 5,     5,
 ifsnow                     = 1,
 icloud                     = 1,
 surface_input_source       = 3,
 num_soil_layers            = 4,
 num_land_cat               = 21,
 sf_urban_physics           = 0,
 sst_update                 = 1,
 tmn_update                 = 1,
 sst_skin                   = 0,
 kfeta_trigger              = 1,
 mfshconv                   = 0,
 prec_acc_dt                = 0,
 sf_lake_physics            = 1,
 use_lakedepth              = 0,
/

&noah_mp
/

&dynamics
 hybrid_opt                 = 2,
 etac                       = 0.1,
 w_damping                  = 1,
 diff_opt                   = 2,      2,
 km_opt                     = 4,      4,
 diff_6th_opt               = 2,      2,
 diff_6th_factor            = 0.12,   0.12,
 base_temp                  = 290.
 damp_opt                   = 3,
 zdamp                      = 5000.,  5000.,
 dampcoef                   = 0.2,    0.2,
 khdif                      = 0,      0,
 kvdif                      = 0,      0,
 non_hydrostatic            = .true., .true.,
 moist_adv_opt              = 1,      1,
 scalar_adv_opt             = 1,      1,
 gwd_opt                    = 1,
 epssm                      = 0.2,    0.2
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
EOF

# ===============================================
# Step 1: Run `real.exe` for initialization
# ===============================================

echo "Running real.exe..."
time mpirun --bind-to none -np $((MAX_CPU < 10 ? MAX_CPU : 10)) ${run_dir}/real.exe
echo "Real.exe completed."

# ===============================================
# Step 2: Data assimilation (optional, WRFDA variable true/false)
# ===============================================
if $RUN_WRFDA; then
  cd ${MAIN_DIR}
  ./run_WRFDA.sh $year $month $day $hour
else
  echo "Running model without data assimilation"
fi

# ===============================================
# Step 3: Run WRF model
# ===============================================

echo "Ready to run WRF.exe"
cd $run_dir
time mpirun --bind-to none -np ${MAX_CPU} ./wrf.exe
if [ ! -f "${run_dir}/wrfout_d02_${eyear}-${emonth}-${eday}_${ehour}:00:00" ]; then
  echo "Error: WRF failed, last output file is missing."
else
  echo "WRF run completed."
fi

# ===============================================
# Step 4: Copy files for next cycle (with DA only)
# ===============================================
if $RUN_WRFDA; then
  echo "Copying fg and VARBC files"
  #First guess files
  fg_date=$(date -d "$s_date $INTERVAL hours" "+%Y-%m-%d %H:%M:%S")
  read fgyear fgmonth fgday fghour fgmin fgsec <<< $(echo $fg_date | tr '-' ' ' | tr ':' ' ')
  cp "$run_dir/wrfout_d01_${fgyear}-${fgmonth}-${fgday}_${fghour}:00:00" "$DA_DIR/rc/" || true
  cp "$run_dir/wrfout_d02_${fgyear}-${fgmonth}-${fgday}_${fghour}:00:00" "$DA_DIR/rc/" || true
  #VARBC file
  cp "$run_dir/da_wrk/VARBC.out" "$DA_DIR/varbc/" || true
fi

echo "Cycle ${year}${month}${day}${hour} WRF run finished"


