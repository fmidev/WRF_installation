#!/bin/bash

# Start timing the installation
start_time=$(date +%s)
echo "Starting WRF installation at $(date)"

# Exit on error, but allow for proper error handling
trap 'echo "ERROR: Command failed with exit code $? at line $LINENO"; exit 1' ERR

# Display banner
echo "================================================================================"
echo "                   WRF Model Automated Installation Script                       "
echo "================================================================================"

# Prompt for installation directory
echo -n "Enter the directory where the libraries and the model should be installed [if empty, installing into /home/$USER/WRF_Model]: "
read user_base_dir

# Define base directory - use default if nothing entered
if [ -z "$user_base_dir" ]; then
    export BASE=/home/$USER/WRF_Model
    echo "Using default installation directory: $BASE"
else
    export BASE=$user_base_dir
    echo "Using installation directory: $BASE"
fi

# Create the base directory if it doesn't exist
[ ! -d "$BASE" ] && mkdir -p "$BASE"

# Prompt for SmartMet server IP address
echo -n "Enter the IP address for the SmartMet server where postprocessed WRF grib files are sent. (optional): "
read smartmet_ip

# Use default if nothing entered
if [ -z "$smartmet_ip" ]; then
    export SMARTMET_IP="0.0.0.0"
else
    export SMARTMET_IP=$smartmet_ip
    echo "SmartMet IP address: $SMARTMET_IP"
fi

# Prompt for GitHub Personal Access Token
echo " "
echo "Installing verification tools requires a GitHub Personal Access Token (PAT)."
echo "This is needed to download R packages from GitHub repositories."
echo "You can create a token at: https://github.com/settings/tokens"
echo "The token needs workflow, gist, user (all) permissions."
echo "Leave empty to skip verification tools installation."
echo -n "Enter your GitHub Personal Access Token: "
read github_token

if [ -z "$github_token" ]; then
    echo "No GitHub token provided. Verification tools installation will be skipped."
    export INSTALL_VERIFICATION=false
else
    echo "GitHub token provided. Verification tools will be installed."
    export INSTALL_VERIFICATION=true
    # Set up the GitHub token in the user's .Renviron file
    echo "Setting up GitHub token in .Renviron file..."
    echo "GITHUB_PAT=$github_token" > ~/.Renviron
    chmod 600 ~/.Renviron
fi

export GIT_REPO=$(pwd)

# Determine number of CPUs for parallel compilation
export NCPUS=$(( $(nproc) - 1 ))
echo "Detected $NCPUS CPU cores, will use for parallel compilation where possible"

# Create a log directory for all installation logs
mkdir -p $BASE/install_logs

# Install required system packages
echo "Installing required packages..."
sudo dnf config-manager --set-enabled crb
sudo dnf makecache
sudo dnf install -y epel-release gcc gfortran g++ htop emacs wget tar perl libxml2-devel \
    m4 chrony libcurl-devel csh ksh git rsync

# Install verification-related system packages
sudo dnf install -y jasper-devel eccodes eccodes-devel proj proj-devel netcdf-devel sqlite sqlite-devel R

echo "y" | sudo dnf update

# Create necessary directories with a single command
echo "Creating directory structure..."
mkdir -p $BASE/{libraries,WPS_GEOG,scripts,tmp,out,logs,GFS,GEN_BE,CRTM_coef,DA_input/{be,ob/{raw_obs,obsproc},rc,varbc},Verification/{scripts,Data/{Forecast,Obs,Static},Results,SQlite_tables}}

# Set compilers and important environment variables once
export CC=gcc
export CXX=g++
export FC=gfortran
export MAKEFLAGS="-j $NCPUS"

# Function to check for errors in compilation logs
check_compile_log() {
    local log_file=$1
    if [ $? -ne 0 ]; then
        echo "Compilation failed. Check the log file: $log_file"
        exit 1
    fi
}

# Function to download, extract, configure, and install libraries with better progress indication
install_library() {
    local url=$1
    local dir_name=$2
    local configure_args=$3
    local file_name=${url##*/}
    local log_dir="$BASE/install_logs"
    local log_file="$log_dir/${dir_name}_install.log"

    if [ -d "$BASE/libraries/$dir_name/install" ] && [ "$(ls -A $BASE/libraries/$dir_name/install)" ]; then
        echo "✓ $dir_name is already installed. Skipping..."
        return
    fi

    echo "🔧 Installing $dir_name..."
    cd $BASE/libraries

    # Check if the file is already downloaded
    if [ ! -f "$file_name" ]; then
        echo "📥 Downloading $file_name..."
        wget --progress=bar:force $url 2>&1 | tee -a "$log_file"
    else
        echo "📦 $file_name already exists. Skipping download..."
    fi

    # Extract the file
    echo "📂 Extracting $file_name..."
    if [[ $file_name == *.zip ]]; then
        unzip -q -o $file_name | tee -a "$log_file"
    else
        tar -xf $file_name | tee -a "$log_file"
    fi

    echo "🔨 Configuring $dir_name..."
    cd $dir_name
    
    if [ $dir_name == "netcdf-fortran-4.6.1" ]; then
        eval ./configure --prefix=$BASE/libraries/netcdf-c-4.9.2/install $configure_args | tee -a "$log_file"
    else
        mkdir -p install
        eval ./configure --prefix=$BASE/libraries/$dir_name/install $configure_args | tee -a "$log_file"
    fi
    
    echo "🏗️ Building $dir_name..."
    make $MAKEFLAGS | tee -a "$log_file"
    echo "📥 Installing $dir_name..."
    make install | tee -a "$log_file"
    echo "✅ $dir_name installed successfully."
}

# Install libraries
install_library "https://zlib.net/current/zlib.tar.gz" "zlib-1.3.1" "" 
install_library "https://download.open-mpi.org/release/open-mpi/v5.0/openmpi-5.0.3.tar.gz" "openmpi-5.0.3" "--with-zlib=$BASE/libraries/zlib-1.3.1/install" 
export PATH=$PATH:$BASE/libraries/openmpi-5.0.3/install/bin
install_library "https://support.hdfgroup.org/ftp/lib-external/szip/2.1.1/src/szip-2.1.1.tar.gz" "szip-2.1.1" "" 
install_library "https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.14/hdf5-1.14.4/src/hdf5-1.14.4-3.tar.gz" "hdf5-1.14.4-3" "--with-zlib=$BASE/libraries/zlib-1.3.1/install/ --with-szlib=$BASE/libraries/szip-2.1.1/install/ --enable-fortran" 
install_library "https://downloads.unidata.ucar.edu/netcdf-c/4.9.2/netcdf-c-4.9.2.tar.gz" "netcdf-c-4.9.2" "--enable-netcdf-4 LDFLAGS=\"-L$BASE/libraries/hdf5-1.14.4-3/install/lib\" CPPFLAGS=\"-I$BASE/libraries/hdf5-1.14.4-3/install/include\" CC=gcc" 
export LD_LIBRARY_PATH=$BASE/libraries/netcdf-c-4.9.2/install/lib
install_library "https://downloads.unidata.ucar.edu/netcdf-fortran/4.6.1/netcdf-fortran-4.6.1.tar.gz" "netcdf-fortran-4.6.1" "LDFLAGS=\"-L$BASE/libraries/netcdf-c-4.9.2/install/lib/\" CPPFLAGS=\"-I$BASE/libraries/netcdf-c-4.9.2/install/include/\" FC=gfortran F77=gfortran"
install_library "http://www.ijg.org/files/jpegsrc.v9f.tar.gz" "jpeg-9f" ""
install_library "https://sourceforge.net/projects/libpng/files/libpng16/1.6.43/libpng-1.6.43.tar.gz" "libpng-1.6.43" ""
install_library "https://www.ece.uvic.ca/~frodo/jasper/software/jasper-1.900.1.zip" "jasper-1.900.1" "--enable-shared --enable-libjpeg"

# WRF installation with better output handling
if [ ! -d "$BASE/WRF" ]; then
    echo "🔧 Installing WRF..."
    cd $BASE
    wget --progress=bar:force https://github.com/wrf-model/WRF/releases/download/v4.6.1/v4.6.1.tar.gz
    tar -xf v4.6.1.tar.gz
    mv WRFV4.6.1 WRF
    cd WRF
    
    # Set all WRF environment variables at once
    export WRF_EM_CORE=1
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5-1.14.4-3/install/
    export jasper=$BASE/libraries/jasper-1.900.1/install/
    export JASPERLIB=$BASE/libraries/jasper-1.900.1/install/lib
    export JASPERINC=$BASE/libraries/jasper-1.900.1/install/include
    export WRF_DA_CORE=0
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    
    echo "🔧 Configuring WRF..."
    echo 34 | ./configure # Automatically select dmpar with GNU compilers
    
    echo "🏗️ Compiling WRF... (output written to terminal and compile.log)"
    # Show progress with a spinner during compilation
    ./compile $MAKEFLAGS em_real 2>&1 | tee compile.log | grep --line-buffered -E 'Compil|Error|SUCCESS'
    check_compile_log "compile.log"
    echo "✅ WRF compiled successfully."
else
    echo "✓ WRF is already installed. Skipping..."
fi

# WPS installation
if [ ! -d "$BASE/WPS" ]; then
    echo "🔧 Installing WPS..."
    cd $BASE
    wget --progress=bar:force https://github.com/wrf-model/WPS/archive/refs/tags/v4.6.0.tar.gz
    tar -xf v4.6.0.tar.gz
    mv WPS-4.6.0/ WPS
    cd WPS
    export jasper=$BASE/libraries/jasper-1.900.1/install/
    export JASPERLIB=$BASE/libraries/jasper-1.900.1/install/lib
    export JASPERINC=$BASE/libraries/jasper-1.900.1/install/include
    export WRF_DIR=$BASE/WRF
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    echo "🔧 Configuring WPS..."
    echo 3 | ./configure # Automatically select dmpar with GNU compilers
    sed -i '/COMPRESSION_LIBS/s|=.*|= -L${BASE}/libraries/jasper-1.900.1/install/lib -L${BASE}/libraries/libpng-1.6.43/install/lib -L${BASE}/libraries/zlib-1.3.1/install/lib -ljasper -lpng -lz|' configure.wps
    sed -i '/COMPRESSION_INC/s|=.*|= -I${BASE}/libraries/jasper-1.900.1/install/include -I${BASE}/libraries/libpng-1.6.43/install/include -I${BASE}/libraries/zlib-1.3.1/install/include|' configure.wps
    echo "🏗️ Compiling WPS... (output written to terminal and compile.log)"
    ./compile $MAKEFLAGS 2>&1 | tee compile.log
    check_compile_log "compile.log"
    echo "✅ WPS compiled successfully."
else
    echo "✓ WPS is already installed. Skipping..."
fi


# Install WRFDA
if [ ! -d "$BASE/WRFDA" ]; then
    echo "🔧 Installing WRFDA..."
    cd $BASE
    tar -xf v4.6.1.tar.gz
    mv WRFV4.6.1/ WRFDA
    cd WRFDA
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5-1.14.4-3/install/
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    export WRFPLUS_DIR=$BASE/WRFPLUS/
    echo "🔧 Configuring WRFDA..."
    echo 34 | ./configure wrfda # Automatically select dmpar with GNU compilers
    echo "🏗️ Compiling WRFDA... (output written to terminal and compile.log)"
    ./compile $MAKEFLAGS all_wrfvar 2>&1 | tee compile.log
    check_compile_log "compile.log"
    echo "✅ WRFDA compiled successfully."
else
    echo "✓ WRFDA is already installed. Skipping..."
fi

# Install NCEPlibs
if [ ! -d "$BASE/libraries/NCEPlibs" ]; then
    echo "🔧 Installing NCEPlibs..."
    cd $BASE/libraries/
    git clone https://github.com/NCAR/NCEPlibs.git
    cd NCEPlibs
    mkdir -p install
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export PNG_INC=$BASE/libraries/libpng-1.6.43/install/include/
    export JASPER_INC=$BASE/libraries/jasper-1.900.1/install/include/
    sed -i '/FFLAGS/s|$| -fallow-argument-mismatch -fallow-invalid-boz|' macros.make.linux.gnu
    echo "🏗️ Compiling NCEPlibs..."
    echo y | ./make_ncep_libs.sh -s linux -c gnu -d $BASE/libraries/NCEPlibs/install/ -o 0 -m 1 -a upp
    echo "✅ NCEPlibs compiled successfully."
else
    echo "✓ NCEPlibs is already installed. Skipping..."
fi

# Install UPP
if [ ! -d "$BASE/UPP" ]; then
    echo "🔧 Installing UPP..."
    cd $BASE
    git clone -b dtc_post_v4.1.0 --recurse-submodules https://github.com/NOAA-EMC/EMC_post UPPV4.1
    mv UPPV4.1 UPP
    cd UPP
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NCEPLIBS_DIR=$BASE/libraries/NCEPlibs/install/
    echo "🔧 Configuring UPP..."
    echo 8 | ./configure # Automatically select gfortran dmpar
    sed -i '/FFLAGS/s|$| -fallow-argument-mismatch -fallow-invalid-boz|' configure
    echo "🏗️ Compiling UPP... (output written to terminal and compile.log)"
    ./compile $MAKEFLAGS 2>&1 | tee compile.log
    check_compile_log "compile.log"
    echo "✅ UPP compiled successfully."
else
    echo "✓ UPP is already installed. Skipping..."
fi

# Function to efficiently apply multiple sed replacements in a file
update_config_file() {
    local file="$1"
    local config_name="$2"
    shift 2
    
    echo "Updating $config_name settings in $file"
    
    # Use sed to make all replacements in one pass
    sed -i "$@" "$file"
}

# Setup UPP more efficiently
if [ -d "$BASE/UPP" ]; then
    echo "Setting up UPP..."
    mkdir -p $BASE/{UPP_out,UPP_wrk/{parm,postprd,wrprd}}
    
    # Copy necessary files
    cp $BASE/UPP/scripts/run_unipost $BASE/UPP_wrk/postprd/
    cp $BASE/UPP/parm/wrf_cntrl.parm $BASE/UPP_wrk/parm/ # for grib1
    cp $GIT_REPO/postxconfig-NT-WRF.txt $BASE/UPP_wrk/parm/ # for grib2 (default)

    # Update run_unipost script with all replacements at once
    update_config_file "$BASE/UPP_wrk/postprd/run_unipost" "UPP" \
        "s|export TOP_DIR=.*|export TOP_DIR=$BASE|" \
        "s|export DOMAINPATH=.*|export DOMAINPATH=$BASE/UPP_wrk|" \
        "s|export UNIPOST_HOME=.*|export UNIPOST_HOME=\${TOP_DIR}/UPP|" \
        "s|export POSTEXEC=.*|export POSTEXEC=\${UNIPOST_HOME}/exec|" \
        "s|export SCRIPTS=.*|export SCRIPTS=\${UNIPOST_HOME}/scripts|" \
        "s|export modelDataPath=.*|export modelDataPath=\${DOMAINPATH}/wrfprd|" \
        "s|export paramFile=.*|export paramFile=\${DOMAINPATH}/parm/wrf_cntrl.parm|" \
        "s|export txtCntrlFile=.*|export txtCntrlFile=\${DOMAINPATH}/parm/postxconfig-NT-WRF.txt|" \
        "s|export dyncore=.*|export dyncore=\"ARW\"|" \
        "s|export inFormat=.*|export inFormat=\"netcdf\"|" \
        "s|export outFormat=.*|export outFormat=\"grib2\"|" \
        "s|export startdate=.*|export startdate=2024070800|" \
        "s|export fhr=.*|export fhr=00|" \
        "s|export lastfhr=.*|export lastfhr=72|" \
        "s|export incrementhr=.*|export incrementhr=01|" \
        "s|export domain_list=.*|export domain_list=\"d01 d02\"|" \
        "s|export RUN_COMMAND=.*|export RUN_COMMAND=\"mpirun -np 10 \${POSTEXEC}/unipost.exe \"|" \
        "s|ln -fs \${DOMAINPATH}/parm/post_avblflds_comm.xml post_avblflds.xml|ln -fs \${UNIPOST_HOME}/parm/post_avblflds_comm.xml post_avblflds.xml|" \
        "s|ln -fs \${DOMAINPATH}/parm/params_grib2_tbl_new params_grib2_tbl_new|ln -fs \${UNIPOST_HOME}/parm/params_grib2_tbl_new params_grib2_tbl_new|"

    echo "✅ UPP setup completed successfully."
else
    echo "❌ UPP is not installed. Skipping UPP setup..."
fi

# Setup CRTM coefficients
if [ -z "$(ls -A $BASE/CRTM_coef)" ]; then
    echo "Setting up CRTM coefficients..."
    mkdir -p $BASE/CRTM_coef
    cd $BASE/CRTM_coef
    if [ ! -f "crtm_coeffs_2.3.0.tar.gz" ]; then
        wget https://www2.mmm.ucar.edu/wrf/users/wrfda/download/crtm_coeffs_2.3.0.tar.gz
    else
        echo "crtm_coeffs_2.3.0.tar.gz already exists. Skipping download..."
    fi
    tar -xvf crtm_coeffs_2.3.0.tar.gz
    echo "CRTM coefficients setup completed."
else
    echo "CRTM coefficients already set up. Skipping..."
fi

# Copy BE file
if [ -d "$BASE/WRFDA" ]; then
    echo "Copying BE file..."
    cp -p $BASE/WRFDA/var/run/be.dat.cv3 $BASE/DA_input/be/be.dat
    echo "BE file copied successfully."
else
    echo "WRFDA is not installed. Skipping BE file setup..."
fi

# Download and extract geographical dataset
if [ -z "$(ls -A $BASE/WPS_GEOG)" ]; then
    echo "Downloading geographical dataset..."
    cd $BASE/WPS_GEOG

    if [ ! -f "geog_complete.tar.gz" ]; then
        wget --progress=bar:force https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz
    else
        echo "geog_complete.tar.gz already exists. Skipping download..."
    fi

    if [ ! -f "geog_high_res_mandatory.tar.gz" ]; then
        wget --progress=bar:force https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz
    else
        echo "geog_high_res_mandatory.tar.gz already exists. Skipping download..."
    fi

    echo "Extracting geographical dataset..."
    tar -zxvf geog_complete.tar.gz --strip-components=1
    tar -zxvf geog_high_res_mandatory.tar.gz --strip-components=1
    echo "Geographical dataset downloaded and extracted successfully."
else
    echo "Geographical dataset already exists. Skipping..."
fi

# Copy and update scripts
echo "Copying run scripts into the scripts directory..."
cp $GIT_REPO/Run_scripts/* $BASE/scripts/
chmod +x $BASE/scripts/*

# Update SmartMet IP address and update all script paths efficiently
echo "Updating configuration in run scripts..."
sed -i "s|smartmet@ip-address|smartmet@$SMARTMET_IP|g" $BASE/scripts/control_run_WRF.sh
sed -i "s|^export BASE_DIR=.*|export BASE_DIR=$BASE|" "$BASE/scripts/env.sh"

# Update all script paths in a loop to avoid repetition
for script in control_run_WRF.sh run_WPS.sh run_WRF.sh execute_upp.sh run_WRFDA.sh clean_wrf.sh get_obs.sh; do
    sed -i "s|^source .*|source $BASE/scripts/env.sh|" "$BASE/scripts/$script"
done

# Crontab setup with improved timezone handling
echo "Setting up crontab for WRF..."
echo "Adjusting crontab times to match system time zone..."

tz_offset=$(date +%z)
tz_sign=${tz_offset:0:1}
tz_hours=${tz_offset:1:2}
tz_minutes=${tz_offset:3:2}

# Remove leading zeros for arithmetic
tz_hours=${tz_hours#0}
tz_minutes=${tz_minutes#0}

# Convert to total offset in hours (including partial hours)
if [ "$tz_sign" = "+" ]; then
    offset_hours=$((tz_hours + tz_minutes / 60))
else
    offset_hours=$((-tz_hours - tz_minutes / 60))
fi

echo "System time zone offset from UTC: ${tz_sign}${tz_hours}:${tz_minutes} (${offset_hours} hours)"

# Adjust each crontab time entry
# Original crontab entries are for UTC times: 6:15, 12:15, 18:15, 0:15
adjust_crontab_time() {
    local original_hour=$1
    local adjusted_hour=$(( (original_hour + offset_hours + 24) % 24 ))
    echo $adjusted_hour
}

time_00=$(adjust_crontab_time 5)
time_06=$(adjust_crontab_time 11)
time_12=$(adjust_crontab_time 17)
time_18=$(adjust_crontab_time 23)

echo "Adjusted crontab job start times, cycle 00: $time_00:00, cycle 06: $time_06:00, cycle 12: $time_12:00, cycle 18: $time_18:00"

# Update the crontab template with all replacements at once
update_config_file "$BASE/scripts/crontab_template" "crontab" \
    "s|#00 5 \* \* \*|#00 $time_00 \* \* \*|" \
    "s|#00 11 \* \* \*|#00 $time_06 \* \* \*|" \
    "s|#00 17 \* \* \*|#00 $time_12 \* \* \*|" \
    "s|#00 23 \* \* \*|#00 $time_18 \* \* \*|" \
    "s|#30 \* \* \* \* /home/wrf/WRF_Model/scripts/clean_wrf.sh|#30 \* \* \* \* $BASE/scripts/clean_wrf.sh|" \
    "s|#0 5 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 00 > /home/wrf/WRF_Model/logs/runlog_00.log|#0 $time_00 \* \* \* $BASE/scripts/control_run_WRF.sh 00 > $BASE/logs/runlog_00.log|" \
    "s|#0 11 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 06 > /home/wrf/WRF_Model/logs/runlog_06.log|#0 $time_06 \* \* \* $BASE/scripts/control_run_WRF.sh 06 > $BASE/logs/runlog_06.log|" \
    "s|#0 17 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 12 > /home/wrf/WRF_Model/logs/runlog_12.log|#0 $time_12 \* \* \* $BASE/scripts/control_run_WRF.sh 12 > $BASE/logs/runlog_12.log|" \
    "s|#0 23 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 18 > /home/wrf/WRF_Model/logs/runlog_18.log|#0 $time_18 \* \* \* $BASE/scripts/control_run_WRF.sh 18 > $BASE/logs/runlog_18.log|"

crontab $BASE/scripts/crontab_template

echo "Crontab for WRF set up successfully but run commands are not active by default."
echo "Remember to activate them by running 'crontab -e' and uncommenting the lines."

# Install verification tools
echo "Checking if system is compatible for verification tools installation..."
# Function to check if the system is using DNF (Fedora/Red Hat based)
is_dnf_system() {
    command -v dnf &> /dev/null
    return $?
}

if [ "$INSTALL_VERIFICATION" = true ] && is_dnf_system; then
    # Install RStudio
    echo "Installing RStudio..."
    cd $BASE/tmp
    wget https://download2.rstudio.org/server/rhel8/x86_64/rstudio-server-rhel-2024.12.1-563-x86_64.rpm
    wget https://download1.rstudio.org/electron/rhel9/x86_64/rstudio-2024.12.1-563-x86_64.rpm
    sudo dnf install -y rstudio-server-rhel-2024.12.1-563-x86_64.rpm
    sudo dnf install -y rstudio-2024.12.1-563-x86_64.rpm

    # Create user R library directory
    mkdir -p ~/R/library
    
    # Create R script for package installation with proper CRAN mirror setting
    cat > $BASE/tmp/install_r_packages.R << 'EOF'
# Check if GITHUB_PAT is available
if (Sys.getenv("GITHUB_PAT") == "") {
  stop("GitHub Personal Access Token not found. Please check your .Renviron file.")
}

# Set a CRAN mirror first
options(repos = c(CRAN = "https://cloud.r-project.org"))

# Install in user's home directory
.libPaths("~/R/library")

# Install required packages
install.packages("remotes")
library(remotes)

# Install GitHub packages using the token
install_github("harphub/harp")
install_github("harphub/Rgrib2")
install.packages("ncdf4")
EOF

    echo "Installing R packages for verification..."
    Rscript $BASE/tmp/install_r_packages.R
    
    rm -f $BASE/tmp/rstudio-server-rhel-2024.12.1-563-x86_64.rpm
    rm -f $BASE/tmp/rstudio-2024.12.1-563-x86_64.rpm
    rm -f $BASE/tmp/install_r_packages.R

    echo "Verification tools installed successfully."
    echo "Your GitHub token has been saved to ~/.Renviron"
elif [ "$INSTALL_VERIFICATION" = true ]; then
    echo "This system does not appear to be using DNF package manager."
    echo "Skipping verification tools installation."
    echo "You need to install verification tools manually."
else
    echo "Verification tools installation was skipped based on your input."
    echo "You can install verification tools manually later."
fi

# Print summary of installation
echo "
===============================================================================
                      WRF INSTALLATION COMPLETED SUCCESSFULLY
===============================================================================

📋 Installation Summary:
- WRF and WPS installed in: $BASE
- Configuration files in: $BASE/scripts
- Log files will be stored in: $BASE/logs
- SmartMet server IP: $SMARTMET_IP
- Verification tools: $([ "$INSTALL_VERIFICATION" = true ] && echo "Installed" || echo "Not installed")

🔍 POST-INSTALLATION CHECKLIST:
1. Define your domain in WPS:
   - Create your domain with WRF domain wizard
   - Edit $BASE/scripts/Run_WPS.sh for your domain specifications

2. Configure your WRF simulation namelist:
   - Edit $BASE/scripts/Run_WRF.sh for physics options and time steps

3. Configure data assimilation (if using):
   - Check $BASE/scripts/Run_WRFDA.sh namelist settings are matching with run_WRF.sh

4. Set up the cron jobs for automation:
   - Run 'crontab -e' to edit your crontab
   - Uncomment the relevant lines in crontab for scheduled runs

5. Set up SSH keys for SmartMet server (if using):
   - Generate SSH keys: ssh-keygen
   - Copy keys to SmartMet: ssh-copy-id smartmet@$SMARTMET_IP
   - Make sure SmartMet server is sending GFS data to the WRF server (ssh key on both sides)

===============================================================================
"

# Calculate and display total runtime
end_time=$(date +%s)
runtime=$((end_time - start_time))
hours=$((runtime / 3600))
minutes=$(( (runtime % 3600) / 60 ))
seconds=$((runtime % 60))

echo "Installation finished at $(date)"
echo "🕒 WRF Installation completed in ${hours}h ${minutes}m ${seconds}s"

