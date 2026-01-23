#!/bin/bash

# Package version configuration
# Change these values to upgrade to newer versions
# Core components
export WRF_VERSION="4.7.1"
export WPS_VERSION="4.6.0"
export UPP_VERSION="dtc_post_v4.1.0"

# Libraries
export ZLIB_VERSION="1.3.1"
export OPENMPI_VERSION="5.0.3"
export SZIP_VERSION="2.1.1"
export HDF5_VERSION="1.14.4-3"
export NETCDF_C_VERSION="4.9.3"
export NETCDF_FORTRAN_VERSION="4.6.2"
export JPEG_VERSION="9f"
export LIBPNG_VERSION="1.6.48"
export JASPER_VERSION="4.2.5"

# CRTM coefficients
export CRTM_COEF_VERSION="2.3.0"

# RStudio
export RSTUDIO_DESKTOP_VERSION="2024.12.1-563"

#Shiny server
export SHINY_SERVER_VERSION="1.5.23.1030"

export GIT_REPO=$(pwd)

# Start timing the installation
start_time=$(date +%s)
echo "Starting WRF installation at $(date)"

# --- sudo rights for installation ---
echo "$USER ALL=(ALL) NOPASSWD:ALL" | sudo tee /etc/sudoers.d/temp_wrf_install > /dev/null

trap '
    sudo rm -f /etc/sudoers.d/temp_wrf_install
    if [ $? -ne 0 ]; then
        echo "ERROR: Command failed with exit code $? at line $LINENO"
        exit 1
    fi
' EXIT

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

# Prompt for country
echo -n "Enter your country name (or abbreviation) for country-specific observation processing (e.g., Finland, Fin, etc.): "
read country_name

# Store country name
if [ -z "$country_name" ]; then
    export COUNTRY=""
    echo "No country specified. Country-specific observation processing will be disabled."
else
    export COUNTRY="$country_name"
    echo "Country set to: $COUNTRY"
    # Create process_local_obs_$COUNTRY.sh template if COUNTRY is set
    mkdir -p "$BASE/scripts"
    cat > "$BASE/scripts/process_local_obs_${COUNTRY}.sh" << 'EOF'
#!/bin/bash
# ===============================================
# Process local observations for WRF DA and verification in COUNTRY_PLACEHOLDER
# Author: 
# Date: 
# ===============================================

# Check for required arguments
if [ "$#" -lt 4 ]; then
    echo "Usage: $0 YYYY MM DD HH"
    exit 1
fi

source BASE_PLACEHOLDER/scripts/env.sh

# Input variables
YYYY=$1  # Year
MM=$2    # Month
DD=$3    # Day
HH=$4    # Hour

# Headers: station_id,latitude,longitude,date,sea_level_pressure,pressure,height,temperature,relative_humidity,wind_speed,wind_direction
# Timeformat: YYYY-MM-DD_HH:MM:SS
OUTPUT_OBS_FILE="${DA_DIR}/ob/raw_obs/local_obs_${YYYY}${MM}${DD}${HH}.csv"

# Headers: valid_dttm,SID,lat,lon,elev,T2m,Td2m,RH2m,Q2m,Pressure,Pcp,Wdir,WS
# Timeformat: YYYY-MM-DD HH:MM:SS
OUTPUT_VERIF_FILE="${BASE_DIR}/Verification/Data/Obs/local_obs${YYYY}${MM}${DD}${HH}00_verif.csv"

#### CODE HERE ##### 

exit 0
EOF
    # Replace placeholders with actual values
    sed -i "s|COUNTRY_PLACEHOLDER|$COUNTRY|g" "$BASE/scripts/process_local_obs_${COUNTRY}.sh"
    sed -i "s|BASE_PLACEHOLDER|$BASE|g" "$BASE/scripts/process_local_obs_${COUNTRY}.sh"
    chmod +x "$BASE/scripts/process_local_obs_${COUNTRY}.sh"
    echo "Created template: $BASE/scripts/process_local_obs_${COUNTRY}.sh"
fi

# Prompt for GitHub Personal Access Token
echo " "
echo "Installing verification tools requires a GitHub Personal Access Token (PAT)."
echo "This is needed to download R packages from GitHub repositories."
echo "You can create a token at: https://github.com/settings/tokens"
echo "The token needs workflow, gist, user (all) permissions."

# Check if a GitHub token already exists
if [ -f ~/.Renviron ] && grep -q "GITHUB_PAT=" ~/.Renviron; then
    existing_token=$(grep "GITHUB_PAT=" ~/.Renviron | cut -d'=' -f2)
    if [ -n "$existing_token" ]; then
        echo " "
        echo "Found existing GitHub Personal Access Token in ~/.Renviron"
        echo -n "Do you want to use the existing token? (y/n) [y]: "
        read use_existing
        use_existing=${use_existing:-y}
        
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            github_token="$existing_token"
            echo "Using existing GitHub token."
        else
            echo -n "Enter your new GitHub Personal Access Token: "
            read github_token
        fi
    else
        echo -n "Enter your GitHub Personal Access Token: "
        read github_token
    fi
else
    echo -n "Enter your GitHub Personal Access Token: "
    read github_token
fi

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
    echo "GitHub token saved to ~/.Renviron"
fi

# Create necessary directories
echo "Creating directory structure..."
mkdir -p $BASE/{libraries,WPS_GEOG,scripts,tmp,out,logs,install_logs,GFS,GEN_BE,CRTM_coef,DA_input/{be,ob/{raw_obs,obsproc},rc,varbc},Verification/{scripts,Data/{Forecast,Obs,Static},Results,SQlite_tables}}

# Create WRF_test directory structure
echo "Creating WRF_test directory structure..."
TEST_BASE=$(dirname $BASE)/WRF_test
mkdir -p $TEST_BASE/{scripts,out,logs,DA_input/{be,ob/{raw_obs,obsproc},rc,varbc},genbe_forecasts}

# Install required system packages
echo "Installing required packages..."
sudo dnf config-manager --set-enabled crb
sudo dnf makecache -y -q
sudo dnf install -y epel-release gcc gfortran g++ emacs wget tar perl libxml2-devel \
    m4 chrony libcurl-devel csh ksh rsync cmake time bc
sudo dnf update -y

# Install verification-related system packages
sudo dnf install -y htop jasper-devel eccodes eccodes-devel proj proj-devel netcdf-devel sqlite sqlite-devel R nco wgrib2 openssl-devel 

# Detect number of CPU cores and save four for test runs and one extra
CPU_COUNT=$(nproc)
MAX_CPU=$((CPU_COUNT - 5))
if [ $MAX_CPU -lt 1 ]; then
    MAX_CPU=1
fi
echo "Detected $CPU_COUNT CPU cores, will use maximum of $MAX_CPU, reserving 4 for test runs"

# Set compilers and important environment variables once
export CC=gcc
export CXX=g++
export FC=gfortran

# Function to check for errors in compilation logs
check_compile_log() {
    local log_file=$1
    if [ $? -ne 0 ]; then
        echo "Compilation failed. Check the log file: $log_file"
        exit 1
    fi
}

# Function to download, extract, configure, and install libraries
install_library() {
    local url=$1
    local version_dir_name=$2
    local generic_name=$3
    local configure_args=$4
    local file_name=${url##*/}
    local log_dir="$BASE/install_logs"
    local log_file="$log_dir/${generic_name}_install.log"

    if [ -d "$BASE/libraries/$generic_name" ] && [ -L "$BASE/libraries/$generic_name" ]; then
        echo "✅ $generic_name is already installed. Skipping..."
        return
    fi

    echo "🔧 Installing $generic_name... (full output written into log file ($log_file))"
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
    tar -xf $file_name > "$log_file" 2>&1
    
    echo "🔨 Configuring $generic_name..."
    
    if [ $generic_name == "jasper" ]; then
        # Special handling for Jasper using CMake
        # Create build directory outside the source tree
        mkdir -p $BASE/libraries/build-${generic_name}
        mkdir -p $BASE/libraries/$version_dir_name/install

        cd $BASE/libraries/build-${generic_name}
        
        # Configure with CMake pointing to source dir
        cmake -H$BASE/libraries/$version_dir_name -B. \
              -DCMAKE_INSTALL_PREFIX=$BASE/libraries/$version_dir_name/install \
              -DCMAKE_BUILD_TYPE=Release \
              -DJAS_ENABLE_DOC=false \
              -DJAS_ENABLE_SHARED=true > "$log_file" 2>&1
        
        # Build and install
        echo "🏗️ Building $generic_name..."
        cmake --build . >> "$log_file" 2>&1
        echo "📥 Installing $generic_name..."
        cmake --build . --target install >> "$log_file" 2>&1
        
        # Return to libraries directory for symlinking
        cd $BASE/libraries
    else
        cd $version_dir_name
        if [ $generic_name == "netcdf-fortran" ]; then
            eval ./configure --prefix=$BASE/libraries/netcdf-c/install $configure_args > "$log_file" 2>&1
        else
            mkdir -p install
            eval ./configure --prefix=$BASE/libraries/$version_dir_name/install $configure_args > "$log_file" 2>&1
        fi  
        echo "🏗️ Building $generic_name..."
        make > "$log_file" 2>&1
        echo "📥 Installing $generic_name..."
        make install > "$log_file" 2>&1
        
        # Return to libraries directory for symlinking
        cd $BASE/libraries
    fi
    
    # Create symbolic link to version-agnostic name
    if [ ! -d "$version_dir_name" ]; then
        echo "ERROR: Directory $version_dir_name not found. Check $log_file. Aborting installation."
        exit 1
    fi
    ln -sf $version_dir_name $generic_name
    
    echo "✅ $generic_name installed successfully."
}

# Install libraries
install_library "https://zlib.net/zlib-${ZLIB_VERSION}.tar.gz" "zlib-${ZLIB_VERSION}" "zlib" "" 
install_library "https://download.open-mpi.org/release/open-mpi/v${OPENMPI_VERSION%.*}/openmpi-${OPENMPI_VERSION}.tar.gz" "openmpi-${OPENMPI_VERSION}" "openmpi" "--with-zlib=$BASE/libraries/zlib/install" 
export PATH=$PATH:$BASE/libraries/openmpi/install/bin
install_library "https://support.hdfgroup.org/ftp/lib-external/szip/${SZIP_VERSION}/src/szip-${SZIP_VERSION}.tar.gz" "szip-${SZIP_VERSION}" "szip" "" 
install_library "https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-${HDF5_VERSION%.*}/hdf5-${HDF5_VERSION%%-*}/src/hdf5-${HDF5_VERSION}.tar.gz" "hdf5-${HDF5_VERSION}" "hdf5" "--with-zlib=$BASE/libraries/zlib/install/ --with-szlib=$BASE/libraries/szip/install/ --enable-fortran" 
install_library "https://downloads.unidata.ucar.edu/netcdf-c/${NETCDF_C_VERSION}/netcdf-c-${NETCDF_C_VERSION}.tar.gz" "netcdf-c-${NETCDF_C_VERSION}" "netcdf-c" "--enable-netcdf-4 LDFLAGS=\"-L$BASE/libraries/hdf5/install/lib\" CPPFLAGS=\"-I$BASE/libraries/hdf5/install/include\" CC=gcc" 
export LD_LIBRARY_PATH=$BASE/libraries/netcdf-c/install/lib
install_library "https://downloads.unidata.ucar.edu/netcdf-fortran/${NETCDF_FORTRAN_VERSION}/netcdf-fortran-${NETCDF_FORTRAN_VERSION}.tar.gz" "netcdf-fortran-${NETCDF_FORTRAN_VERSION}" "netcdf-fortran" "LDFLAGS=\"-L$BASE/libraries/netcdf-c/install/lib/\" CPPFLAGS=\"-I$BASE/libraries/netcdf-c/install/include/\" FC=gfortran F77=gfortran"
install_library "http://www.ijg.org/files/jpegsrc.v${JPEG_VERSION}.tar.gz" "jpeg-${JPEG_VERSION}" "jpeg" ""
install_library "https://github.com/pnggroup/libpng/archive/refs/tags/v${LIBPNG_VERSION}.tar.gz" "libpng-${LIBPNG_VERSION}" "libpng" ""
install_library "https://github.com/jasper-software/jasper/releases/download/version-${JASPER_VERSION}/jasper-${JASPER_VERSION}.tar.gz" "jasper-${JASPER_VERSION}" "jasper" ""

# WRF installation
if [ ! -d "$BASE/WRF" ]; then
    echo "🔧 Installing WRF..."
    cd $BASE
    mkdir -p $BASE/tmp
    
    # Check if tarball already exists in tmp directory
    if [ -f "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz" ]; then
        echo "📦 WRF tarball already exists in $BASE/tmp. Using existing file..."
        cp $BASE/tmp/v${WRF_VERSION}_WRF.tar.gz ./v${WRF_VERSION}.tar.gz
    else
        echo "📥 Downloading WRF tarball..."
        wget --progress=bar:force https://github.com/wrf-model/WRF/releases/download/v${WRF_VERSION}/v${WRF_VERSION}.tar.gz
        # Save a copy to tmp directory
        cp v${WRF_VERSION}.tar.gz $BASE/tmp/v${WRF_VERSION}_WRF.tar.gz
    fi
    
    tar -xf v${WRF_VERSION}.tar.gz
    mv WRFV${WRF_VERSION} WRF
    cd WRF
    
    # Set all WRF environment variables
    export WRF_EM_CORE=1
    export NETCDF=$BASE/libraries/netcdf-c/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5/install
    export jasper=$BASE/libraries/jasper/install
    export JASPERLIB=$BASE/libraries/jasper/install/lib
    export JASPERINC=$BASE/libraries/jasper/install/include
    export WRF_DA_CORE=0
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    
    echo "🔧 Configuring WRF..."
    echo 34 | ./configure # Automatically select dmpar with GNU compilers
    
    echo "🏗️ Compiling WRF... (full output written to ${BASE}/WRF/compile.log)"
    # Show progress with a spinner during compilation
    ./compile em_real 2>&1 | tee compile.log | grep --line-buffered -E 'Compil|Error|SUCCESS'
    check_compile_log "compile.log"

    cd $BASE
    rm -f v${WRF_VERSION}.tar.gz

    # Check if the critical executables exist
    if [ ! -f "$BASE/WRF/main/wrf.exe" ] || [ ! -f "$BASE/WRF/main/real.exe" ]; then
        echo "❌ ERROR: WRF compilation failed. Could not find wrf.exe or real.exe in $BASE/WRF/main."
        echo "Check the compilation log for errors: $BASE/WRF/compile.log"
        echo "If you want to recompile WRF, remove the WRF directory and rerun the installation script."
        exit 1
    fi

    echo "✅ WRF compiled successfully."
else
    echo "✅ WRF is already installed. Skipping..."
    
    # Check if executables exist in existing installation
    if [ ! -f "$BASE/WRF/main/wrf.exe" ] || [ ! -f "$BASE/WRF/main/real.exe" ]; then
        echo "❌ ERROR: Existing WRF installation appears to be incomplete. Could not find wrf.exe or real.exe in $BASE/WRF/main."
        echo "Consider removing the WRF directory and rerunning the installation script."
        exit 1
    fi
fi

# WPS installation
if [ ! -d "$BASE/WPS" ]; then
    echo "🔧 Installing WPS..."
    cd $BASE
    
    # Check if tarball already exists in tmp directory
    if [ -f "$BASE/tmp/v${WPS_VERSION}_WPS.tar.gz" ]; then
        echo "📦 WPS tarball already exists in $BASE/tmp. Using existing file..."
        cp $BASE/tmp/v${WPS_VERSION}_WPS.tar.gz ./v${WPS_VERSION}.tar.gz
    else
        echo "📥 Downloading WPS tarball..."
        wget --progress=bar:force https://github.com/wrf-model/WPS/archive/refs/tags/v${WPS_VERSION}.tar.gz
        # Save a copy to tmp directory
        cp v${WPS_VERSION}.tar.gz $BASE/tmp/v${WPS_VERSION}_WPS.tar.gz
    fi
    
    tar -xf v${WPS_VERSION}.tar.gz
    mv WPS-${WPS_VERSION}/ WPS
    cd WPS

    export jasper=$BASE/libraries/jasper/install
    export JASPERLIB=$BASE/libraries/jasper/install/lib
    export JASPERINC=$BASE/libraries/jasper/install/include
    export WRF_DIR=$BASE/WRF
    export NETCDF=$BASE/libraries/netcdf-c/install

    echo "🔧 Configuring WPS..."
    echo 3 | ./configure # Automatically select dmpar with GNU compilers
    sed -i '/COMPRESSION_LIBS/s|=.*|= -L${BASE}/libraries/jasper/install/lib -L${BASE}/libraries/libpng/install/lib -L${BASE}/libraries/zlib/install/lib -ljasper -lpng -lz|' configure.wps
    sed -i '/COMPRESSION_INC/s|=.*|= -I${BASE}/libraries/jasper/install/include -I${BASE}/libraries/libpng/install/include -I${BASE}/libraries/zlib/install/include|' configure.wps
    echo "🏗️ Compiling WPS... (full output written to ${BASE}/WPS/compile.log)"
    ./compile 2>&1 | tee compile.log | grep --line-buffered -E 'Compil|Error|SUCCESS'
    check_compile_log "compile.log"

    cd $BASE
    rm -f v${WPS_VERSION}.tar.gz

    # Check if the critical executables exist
    if [ ! -f "$BASE/WPS/geogrid.exe" ] || [ ! -f "$BASE/WPS/metgrid.exe" ] || [ ! -f "$BASE/WPS/ungrib.exe" ]; then
        echo "❌ ERROR: WPS compilation failed. Could not find one or more of the required executables (geogrid.exe, metgrid.exe, ungrib.exe) in $BASE/WPS."
        echo "Check the compilation log for errors: $BASE/WPS/compile.log"
        echo "If you want to recompile WPS, remove the WPS directory and rerun the installation script."
        exit 1
    fi

    echo "✅ WPS compiled successfully."
else
    echo "✅ WPS is already installed. Skipping..."
    
    # Check if executables exist in existing installation
    if [ ! -f "$BASE/WPS/geogrid.exe" ] || [ ! -f "$BASE/WPS/metgrid.exe" ] || [ ! -f "$BASE/WPS/ungrib.exe" ]; then
        echo "❌ ERROR: Existing WPS installation appears to be incomplete. Could not find one or more of the required executables (geogrid.exe, metgrid.exe, ungrib.exe) in $BASE/WPS."
        echo "Consider removing the WPS directory and rerunning the installation script."
        exit 1
    fi
fi

# Install WRFDA
if [ ! -d "$BASE/WRFDA" ]; then
    echo "🔧 Installing WRFDA..."
    cd $BASE
    
    # Check if WRF tarball exists in tmp directory (WRFDA uses the same tarball as WRF)
    if [ -f "$BASE/tmp/v${WRF_VERSION}_WRF.tar.gz" ]; then
        echo "📦 WRF tarball already exists in $BASE/tmp. Using for WRFDA..."
        cp $BASE/tmp/v${WRF_VERSION}_WRF.tar.gz ./v${WRF_VERSION}.tar.gz
    else
        echo "📥 Downloading WRF tarball for WRFDA..."
        wget --progress=bar:force https://github.com/wrf-model/WRF/releases/download/v${WRF_VERSION}/v${WRF_VERSION}.tar.gz
        # Save a copy to tmp directory
        cp v${WRF_VERSION}.tar.gz $BASE/tmp/v${WRF_VERSION}_WRF.tar.gz
    fi
    
    tar -xf v${WRF_VERSION}.tar.gz
    mv WRFV${WRF_VERSION}/ WRFDA
    cd WRFDA

    export NETCDF=$BASE/libraries/netcdf-c/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5/install
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    
    # Patch SEVIRI observation reader to support Meteosat-12 (MSG-5)
    echo "🔧 Patching SEVIRI reader for Meteosat-12"
    SEVIRI_FILE="var/da/da_radiance/da_read_obs_bufrseviri.inc"
    if [ -f "$SEVIRI_FILE" ]; then
        # Add comment for SAID 71 (Meteosat-12/MSG-5)
        sed -i '/SAID 70 is meteosat-11 or msg-4/a\	! SAID 71 is meteosat-12 or msg-5' "$SEVIRI_FILE"
        # Update kidsat range check from 70 to 71
        sed -i 's/if ( ( kidsat > 70) .or. ( kidsat < 55) ) then/if ( ( kidsat > 71) .or. ( kidsat < 55) ) then/' "$SEVIRI_FILE"
        # Add satellite_id mapping for kidsat 71
        sed -i '/else if ( kidsat == 70 ) then/,/satellite_id = 4/a\	else if ( kidsat == 71 ) then\n            satellite_id = 5' "$SEVIRI_FILE"
        echo "✅ SEVIRI reader patched successfully"
    else
        echo "⚠️  WARNING: SEVIRI file not found at $SEVIRI_FILE"
    fi
    
    echo "🔧 Configuring WRFDA..."
    echo 34 | ./configure wrfda # Automatically select dmpar with GNU compilers
    echo "🏗️ Compiling WRFDA... (full output written to ${BASE}/WRFDA/compile.log)"
    ./compile all_wrfvar 2>&1 | tee compile.log | grep --line-buffered -E 'Compil|Error|SUCCESS'
    check_compile_log "compile.log"
    
    cd $BASE 
    rm -f v${WRF_VERSION}.tar.gz

    # Check if the critical executables exist
    if [ ! -f "$BASE/WRFDA/var/da/da_wrfvar.exe" ] || [ ! -f "$BASE/WRFDA/var/da/da_update_bc.exe" ]; then
        echo "❌ ERROR: WRFDA compilation failed. Could not find da_wrfvar.exe or da_update_bc.exe in $BASE/WRFDA/var/da/"
        echo "Check the compilation log for errors: $BASE/WRFDA/compile.log"
        echo "If you want to recompile WRFDA, remove the WRFDA directory and rerun the installation script."
        exit 1
    fi

    echo "✅ WRFDA compiled successfully."
else
    echo "✅ WRFDA is already installed. Skipping..."
    
    # Check if executables exist in existing installation
    if [ ! -f "$BASE/WRFDA/var/da/da_wrfvar.exe" ] || [ ! -f "$BASE/WRFDA/var/da/da_update_bc.exe" ]; then
        echo "❌ ERROR: Existing WRFDA installation appears to be incomplete. Could not find da_wrfvar.exe or da_update_bc.exe in $BASE/WRFDA/var/da/"
        echo "Consider removing the WRFDA directory and rerunning the installation script."
        exit 1
    fi
fi

# Function to perform git clone with retry mechanism
git_clone_with_retry() {
    local repo_url=$1
    local target_dir=$2
    local branch=$3
    local recurse=$4
    local max_retries=5
    local retry_delay=30
    local attempt=1
    local exit_code=1
    local clone_cmd="git clone"
    
    # Add branch option if specified
    if [ -n "$branch" ]; then
        clone_cmd="$clone_cmd -b $branch"
    fi
    
    # Add recurse-submodules if specified
    if [ "$recurse" = "true" ]; then
        clone_cmd="$clone_cmd --recurse-submodules"
    fi
    
    # Add depth=1 to speed up the clone by getting only latest commit
    clone_cmd="$clone_cmd --depth=1"
    
    # Final command with URL and target directory
    clone_cmd="$clone_cmd $repo_url $target_dir"
    
    echo "Cloning $repo_url to $target_dir"
    
    while [ $attempt -le $max_retries ] && [ $exit_code -ne 0 ]; do
        if [ $attempt -gt 1 ]; then
            echo "Clone attempt $attempt of $max_retries (waiting ${retry_delay}s before retry)..."
            sleep $retry_delay
            # Increase delay for next attempt
            retry_delay=$((retry_delay * 2))
        fi
        
        # Set a longer timeout for Git operations
        export GIT_HTTP_LOW_SPEED_LIMIT=1000
        export GIT_HTTP_LOW_SPEED_TIME=60
        
        eval $clone_cmd
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "Git clone completed successfully."
            return 0
        fi
        
        attempt=$((attempt+1))
    done
    
    if [ $exit_code -ne 0 ]; then
        echo "ERROR: Failed to clone repository after $max_retries attempts."
        return 1
    fi
}

# Install NCEPlibs
if [ ! -d "$BASE/libraries/NCEPlibs/install" ] || [ -z "$(ls -A $BASE/libraries/NCEPlibs/install)" ]; then
    echo "🔧 Installing NCEPlibs..."
    cd $BASE/libraries/
    
    # Create NCEPlibs directory if it doesn't exist
    mkdir -p $BASE/libraries/NCEPlibs
    
    if [ ! -d "$BASE/libraries/NCEPlibs/.git" ]; then
        # Only clone if not already cloned
        cd $BASE/libraries/
        if ! git_clone_with_retry "https://github.com/NCAR/NCEPlibs.git" "NCEPlibs" "" "false"; then
            echo "Failed to clone NCEPlibs repository. Please check your internet connection and try again."
            exit 1
        fi
    else
        echo "NCEPlibs repository already cloned. Using existing repository."
    fi
    
    cd $BASE/libraries/NCEPlibs
    mkdir -p install
    export NETCDF=$BASE/libraries/netcdf-c/install
    export PNG_INC=$BASE/libraries/libpng/install/include
    export JASPER_INC=$BASE/libraries/jasper/install/include
    sed -i '/FFLAGS/s|$| -fallow-argument-mismatch -fallow-invalid-boz|' macros.make.linux.gnu
    echo "🏗️ Compiling NCEPlibs... (full output written to ${BASE}/libraries/NCEPlibs/compile.log)"
    echo y | ./make_ncep_libs.sh -s linux -c gnu -d $BASE/libraries/NCEPlibs/install/ -o 0 -m 1 -a upp > compile.log 2>&1
    echo "✅ NCEPlibs compiled successfully."
else
    echo "✅ NCEPlibs is already installed. Skipping..."
    echo "If you want to recompile NCEPlibs, remove the $BASE/libraries/NCEPlibs/install directory and rerun the installation script."
fi

# Install UPP
if [ ! -d "$BASE/UPP" ]; then
    echo "🔧 Installing UPP..."
    cd $BASE
    
    if ! git_clone_with_retry "https://github.com/NOAA-EMC/EMC_post" "UPP" "${UPP_VERSION}" "true"; then
        echo "Failed to clone UPP repository. Please check your internet connection and try again."
        exit 1
    fi
    
    cd UPP
    export NETCDF=$BASE/libraries/netcdf-c/install
    export NCEPLIBS_DIR=$BASE/libraries/NCEPlibs/install
    echo "🔧 Configuring UPP..."
    echo 8 | ./configure # Automatically select gfortran dmpar
    sed -i '/^FFLAGS\(.*\)=/s/=\(.*\)/= -fallow-argument-mismatch -fallow-invalid-boz \1/' configure.upp
    echo "🏗️ Compiling UPP... (full output written to ${BASE}/UPP/compile.log)"
    ./compile 2>&1 | tee compile.log | grep --line-buffered -E 'Compil|Error|SUCCESS'
    check_compile_log "compile.log"
    
    # Check if the critical executable exists
    if [ ! -f "$BASE/UPP/exec/unipost.exe" ]; then
        echo "❌ ERROR: UPP compilation failed. Could not find unipost.exe in $BASE/UPP/exec/"
        echo "Check the compilation log for errors: $BASE/UPP/compile.log"
        echo "If you want to recompile UPP, remove the UPP directory and rerun the installation script."
        exit 1
    fi
    
    echo "✅ UPP compiled successfully."
else
    echo "✅ UPP is already installed. Skipping..."
    
    # Check if the executable exists in existing installation
    if [ ! -f "$BASE/UPP/exec/unipost.exe" ]; then
        echo "❌ ERROR: Existing UPP installation appears to be incomplete. Could not find unipost.exe in $BASE/UPP/exec/"
        echo "Consider removing the UPP directory and rerunning the installation script."
        exit 1
    fi
fi

# Setup UPP
if [ -d "$BASE/UPP" ]; then
    echo "Setting up UPP..."
    mkdir -p $BASE/{UPP_out,UPP_wrk/{parm,postprd,wrfprd}}
    
    # Copy necessary files
    cp $BASE/UPP/scripts/run_unipost $BASE/UPP_wrk/postprd/
    cp $BASE/UPP/parm/wrf_cntrl.parm $BASE/UPP_wrk/parm/ # for grib1
    cp $GIT_REPO/postxconfig-NT-WRF.txt $BASE/UPP_wrk/parm/ # for grib2 (default)

    UNIPOST=$BASE/UPP_wrk/postprd/run_unipost

    echo "Updating UPP settings in $UNIPOST"
    sed -i "s|export TOP_DIR=.*|export TOP_DIR=$BASE|" "$UNIPOST"
    sed -i "s|export DOMAINPATH=.*|export DOMAINPATH=$BASE/UPP_wrk|" "$UNIPOST"
    sed -i "s|export UNIPOST_HOME=.*|export UNIPOST_HOME=\${TOP_DIR}/UPP|" "$UNIPOST"
    sed -i "s|export POSTEXEC=.*|export POSTEXEC=\${UNIPOST_HOME}/exec|" "$UNIPOST"
    sed -i "s|export SCRIPTS=.*|export SCRIPTS=\${UNIPOST_HOME}/scripts|" "$UNIPOST"
    sed -i "s|export modelDataPath=.*|export modelDataPath=\${DOMAINPATH}/wrfprd|" "$UNIPOST"
    sed -i "s|export paramFile=.*|export paramFile=\${DOMAINPATH}/parm/wrf_cntrl.parm|" "$UNIPOST"
    sed -i "s|export txtCntrlFile=.*|export txtCntrlFile=\${DOMAINPATH}/parm/postxconfig-NT-WRF.txt|" "$UNIPOST"
    sed -i "s|export dyncore=.*|export dyncore=\"ARW\"|" "$UNIPOST"
    sed -i "s|export inFormat=.*|export inFormat=\"netcdf\"|" "$UNIPOST"
    sed -i "s|export outFormat=.*|export outFormat=\"grib2\"|" "$UNIPOST"
    sed -i "s|export startdate=.*|export startdate=2024070800|" "$UNIPOST"
    sed -i "s|export fhr=.*|export fhr=00|" "$UNIPOST"
    sed -i "s|export lastfhr=.*|export lastfhr=72|" "$UNIPOST"
    sed -i "s|export incrementhr=.*|export incrementhr=01|" "$UNIPOST"
    sed -i "s|export domain_list=.*|export domain_list=\"d01 d02\"|" "$UNIPOST"
    sed -i "s|export RUN_COMMAND=.*|export RUN_COMMAND=\"mpirun --bind-to none -np \\\$((MAX_CPU < 20 ? MAX_CPU : 20)) \${POSTEXEC}/unipost.exe \"|" "$UNIPOST"
    sed -i "s|ln -fs \${DOMAINPATH}/parm/post_avblflds_comm.xml post_avblflds.xml|ln -fs \${UNIPOST_HOME}/parm/post_avblflds.xml post_avblflds.xml|" "$UNIPOST"
    sed -i "s|ln -fs \${DOMAINPATH}/parm/params_grib2_tbl_new params_grib2_tbl_new|ln -fs \${UNIPOST_HOME}/parm/params_grib2_tbl_new params_grib2_tbl_new|" "$UNIPOST"

    echo "✅ UPP setup completed successfully."
else
    echo "❌ UPP is not installed. Skipping UPP setup..."
fi

# Install RStudio and Shiny server (only if verification tools are requested)
if [ "$INSTALL_VERIFICATION" = true ]; then

    echo "Installing RStudio and Shiny server..."
    cd $BASE/tmp
    # Download RStudio Desktop only if not already present
    if [ ! -f "rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm" ]; then
        wget https://download1.rstudio.org/electron/rhel9/x86_64/rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm
    else
        echo "rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm already exists. Skipping download..."
    fi
    # Download Shiny Server only if not already present
    if [ ! -f "shiny-server-${SHINY_SERVER_VERSION}-x86_64.rpm" ]; then
        wget https://download3.rstudio.org/centos8/x86_64/shiny-server-${SHINY_SERVER_VERSION}-x86_64.rpm
    else
        echo "shiny-server-${SHINY_SERVER_VERSION}-x86_64.rpm already exists. Skipping download..."
    fi
    sudo dnf install -y rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm
    sudo dnf install -y shiny-server-${SHINY_SERVER_VERSION}-x86_64.rpm

    # --- R PACKAGE INSTALLATION ---
    echo "Installing required R packages for verification tools..."
    mkdir -p ~/R/library

    cat > $BASE/tmp/install_r_packages.R << 'EOF'
# Check if GITHUB_PAT is available
if (Sys.getenv("GITHUB_PAT") == "") {
  stop("GitHub Personal Access Token not found. Please check your .Renviron file.")
}
options(repos = c(CRAN = "https://cloud.r-project.org"))
.libPaths("~/R/library")
install.packages("shiny")
install.packages("jsonlite")
install.packages("remotes")
library(remotes)
install_github("harphub/harp")
install_github("harphub/Rgrib2")
install.packages("ncdf4")
install.packages("optparse")
install.packages("DT")
install.packages("plotly")
install.packages("zoo")
install.packages("lubridate")
install.packages("viridis")
install.packages("bslib")
EOF

    echo "Installing R packages for verification..."
    Rscript $BASE/tmp/install_r_packages.R > $BASE/install_logs/install_r_packages.log 2>&1

    rm -f $BASE/tmp/install_r_packages.R

    echo "R packages for verification installed successfully."
    echo "Your GitHub token has been saved to ~/.Renviron"

    # --- CONTINUE WITH SHINY APP DEPLOYMENT AND CONFIGURATION ---
    echo "Setting up Shiny user environment and permissions..."
    sudo echo "R_LIBS_USER=/home/$USER/R/library/" | sudo tee -a /home/shiny/.Renviron
    sudo chown shiny:shiny /home/shiny/.Renviron
    sudo setfacl -m u:shiny:rx /home/$USER
    sudo setfacl -R -m u:shiny:rx /home/$USER/R
    
    # Deploy harpVis Shiny app
    echo "Deploying harpVis Shiny app..."
    HARPVIS_APP_DIR="/srv/shiny-server/harpvis"
    sudo mkdir -p "$HARPVIS_APP_DIR"
    sudo cp "$GIT_REPO/Shiny/harpvis.R" "$HARPVIS_APP_DIR/app.R"
    sudo chown -R shiny:shiny "$HARPVIS_APP_DIR"
    sudo chmod -R 755 "$HARPVIS_APP_DIR"
    echo "harpVis Shiny app deployed successfully."
    
    # Deploy WRF Visualization App
    echo "Deploying WRF Visualization app..."
    WRF_VIZ_APP_DIR="/srv/shiny-server/wrf-viz"
    sudo mkdir -p "$WRF_VIZ_APP_DIR"
    sudo cp "$GIT_REPO/Shiny/wrf_viz.R" "$WRF_VIZ_APP_DIR/app.R"
    
    # Update the default WRF output directory path in the app
    sudo sed -i "s|/wrf/WRF_Model/out|$BASE/out|g" "$WRF_VIZ_APP_DIR/app.R"
    
    # Set proper permissions
    sudo chown -R shiny:shiny "$WRF_VIZ_APP_DIR"
    sudo chmod -R 755 "$WRF_VIZ_APP_DIR"
    echo "WRF Visualization app deployed successfully."
    
    # Deploy Landing Page App
    echo "Deploying WRF Portal landing page..."
    LANDING_APP_DIR="/srv/shiny-server"
    sudo cp "$GIT_REPO/Shiny/landing_app.R" "$LANDING_APP_DIR/index.R"
    sudo chown shiny:shiny "$LANDING_APP_DIR/index.R"
    sudo chmod -R 755 "$LANDING_APP_DIR"
    echo "Landing page deployed successfully."

    # Final Shiny server restart to load all apps
    echo "Restarting Shiny server with all applications..."
    sudo systemctl restart shiny-server
    sudo systemctl enable shiny-server
fi

# Setup git repository to track configuration and script files
setup_git_repository() {
    echo "🔧 Setting up git repository to track configuration and script files..."
    
    # Create a git repository in the BASE directory
    cd $BASE
    git init
    
    # Create a .gitignore file that ignores everything except specific directories/files
    cat > .gitignore << EOL
# Ignore everything by default
/*

# Allow specific directories and files
!/scripts/
!/UPP_wrk/
/UPP_wrk/*
!/UPP_wrk/parm/
!/UPP_wrk/postprd/
/UPP_wrk/postprd/*
!/UPP_wrk/postprd/run_unipost
!/Verification/
/Verification/*
!/Verification/scripts/

# Still ignore any compiled files or temporary files in the allowed directories
*.exe
*.o
*.mod
*.log
*.tmp
*.swp
EOL

    # Add the specified directories and files
    git add scripts/
    git add UPP_wrk/parm/
    git add UPP_wrk/postprd/run_unipost
    git add Verification/scripts/
    
    # Commit the initial state
    git config --local user.name "WRF admin"
    git config --local user.email "<>"
    git commit -m "Initial commit: tracking WRF configuration and script files"
    
    echo "✅ Git repository set up successfully at $BASE"
    echo "   Tracking: scripts/, UPP_wrk/parm/, UPP_wrk/postprd/run_unipost, and Verification/scripts/"
}

# Setup CRTM coefficients
if [ -z "$(ls -A $BASE/CRTM_coef)" ]; then
    echo "Setting up CRTM coefficients..."
    mkdir -p $BASE/CRTM_coef
    cd $BASE/CRTM_coef
    if [ ! -f "crtm_coeffs_${CRTM_COEF_VERSION}.tar.gz" ]; then
        wget https://www2.mmm.ucar.edu/wrf/users/wrfda/download/crtm_coeffs_${CRTM_COEF_VERSION}.tar.gz
    else
        echo "crtm_coeffs_${CRTM_COEF_VERSION}.tar.gz already exists. Skipping download..."
    fi
    tar -xvf crtm_coeffs_${CRTM_COEF_VERSION}.tar.gz
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
    tar -zxf geog_complete.tar.gz --strip-components=1
    tar -zxf geog_high_res_mandatory.tar.gz --strip-components=1
    echo "Geographical dataset downloaded and extracted successfully."
else
    echo "Geographical dataset already exists. Skipping..."
fi

# Copy and update scripts
echo "Copying run scripts into the scripts directory..."
cp $GIT_REPO/Run_scripts/* $BASE/scripts/ 2>/dev/null || true
chmod -R +x $BASE/scripts/

# Update SmartMet IP address in production scripts
echo "Updating configuration in production scripts..."
sed -i "s|smartmet@ip-address|smartmet@$SMARTMET_IP|g" $BASE/scripts/control_run_WRF.sh

# Configure env.sh with CPU cores, BASE_DIR, and other settings
echo "Configuring env.sh..."
sed -i "s|^export BASE_DIR=.*|export BASE_DIR=$BASE|" "$BASE/scripts/env.sh"
sed -i "s|^export MAX_CPU=.*|export MAX_CPU=$MAX_CPU|" "$BASE/scripts/env.sh"
sed -i "s|^export COUNTRY=.*|export COUNTRY=\"$COUNTRY\"|" "$BASE/scripts/env.sh"

# Update all production script paths to source the configured env.sh
echo "Updating script paths in production scripts..."
for script in control_run_WRF.sh run_WRF.sh execute_upp.sh run_WRFDA.sh clean_wrf.sh get_obs.sh verification.sh; do
    if [ -f "$BASE/scripts/$script" ]; then
        sed -i "s|^source .*|source $BASE/scripts/env.sh|" "$BASE/scripts/$script"
    fi
done

echo "✅ Production scripts configured successfully"

echo "Creating WRF_test scripts..."

# Calculate TEST CPU range (starts after production CPUs)
TEST_CPU_START=$MAX_CPU
TEST_CPU_END=$((CPU_COUNT - 1))
TEST_MAX_CPU=$((TEST_CPU_END - TEST_CPU_START + 1))

# Common sed substitutions for test scripts
COMMON_SUBS='-e "s|^# Author:.*|# Author: Mikael Hasu|" -e "s|^# Date:.*|# Date: November 2025|" -e "s|source .*/env.sh|source $TEST_BASE/scripts/env_test.sh|"'
# Update CPU_SUBS to replace MAX_CPU references
CPU_SUBS='-e "s|mpirun -np \$((MAX_CPU|mpirun -np \${TEST_MAX_CPU}|g" -e "s|mpirun -np \${MAX_CPU}|mpirun -np \${TEST_MAX_CPU}|g"'

# Create env_test.sh with GEN_BE configuration
sed -e "s|^# ===============================================|# ===============================================\n# WRF_test Environment Configuration\n# Runs: 00 and 12 UTC (twice daily) - Configured for GEN_BE B matrix creation\n# Author: Mikael Hasu\n# Date: November 2025\n# ===============================================\n\n# Base directories\n#|" \
    -e "s|^export BASE_DIR=.*|export BASE_DIR=$BASE  # Production base\nexport TEST_BASE_DIR=$TEST_BASE  # Test suite base|" \
    -e "s|^export LIB_DIR=.*|export LIB_DIR=\$BASE_DIR/libraries  # Shared libraries with production|" \
    -e "s|^export DA_DIR=.*|export DA_DIR=\$TEST_BASE_DIR/DA_input|" \
    -e "s|^export MAIN_DIR=.*|export MAIN_DIR=\$TEST_BASE_DIR/scripts|" \
    -e "s|^export PROD_DIR=.*|export PROD_DIR=\$TEST_BASE_DIR/out|" \
    -e "s|^export MAX_CPU=.*|export TEST_MAX_CPU=$TEST_MAX_CPU  # CPU allocation for test runs|" \
    -e "s|^export RUN_UPP=.*|export RUN_UPP=false  # No post-processing needed for testing|" \
    -e "s|^export RUN_COPY_GRIB=.*|export RUN_COPY_GRIB=false  # No SmartMet copying for test runs|" \
    -e "s|^export RUN_WRFDA=.*|export RUN_WRFDA=false  # Data assimilation OFF for GEN_BE|" \
    -e "s|^export LEADTIME=.*|export LEADTIME=24  # 24-hour forecasts for GEN_BE|" \
    -e "s|^export SAVE_GENBE_FORECASTS=.*|export SAVE_GENBE_FORECASTS=true  # Save 12h and 24h forecasts for B matrix generation|" \
    $BASE/scripts/env.sh > $TEST_BASE/scripts/env_test.sh

# Add GEN_BE specific settings to env_test.sh
cat >> $TEST_BASE/scripts/env_test.sh << 'GENBE_EOF'

# ===============================================
# GEN_BE Configuration for B Matrix Creation
# ===============================================
export GENBE_DIR="${TEST_BASE_DIR}/GEN_BE"
export GENBE_FC_DIR="${TEST_BASE_DIR}/genbe_forecasts"  # Storage for forecast differences
export SAVE_GENBE_FORECASTS=true  # Enable saving forecasts for GEN_BE
export RUN_GENBE=false  # Set to true when ready to generate BE statistics
export NL_CV_OPTIONS=5  # CV5 (default), can be changed to 7 for CV7
export BIN_TYPE=5  # Binning type for calculating statistics
export NUM_LEVELS=44
export GENBE_FCST_RANGE1=12  # First forecast range (hours)
export GENBE_FCST_RANGE2=24  # Second forecast range (hours)

GENBE_EOF

# Create control_run_WRF_test.sh with GEN_BE support
eval sed $COMMON_SUBS \
    -e '"s|WRF Control Script|WRF_test Control Script|"' \
    -e '"s|\${BASE_DIR}/logs/main|\${TEST_BASE_DIR}/logs/main|g"' \
    -e '"s|\${BASE_DIR}/logs/historical|\${TEST_BASE_DIR}/logs/historical|g"' \
    -e '"/^hour=\$1/a\\\n\\\n# Validate input\\\nif [[ \"\$hour\" != \"00\" \&\& \"\$hour\" != \"12\" ]]; then\\\n    echo \"Error: WRF_test runs only at 00 and 12 UTC\"\\\n    echo \"Usage: \$0 <hour>\"\\\n    echo \"Example: \$0 00\"\\\n    exit 1\\\nfi"' \
    -e '"s|WRF Run started|WRF_test Run started|"' \
    -e '"/WRF_test Run started/a\\\necho \"Note: This is a TEST run using \${TEST_MAX_CPU} CPUs\" >> \${TEST_BASE_DIR}/logs/main.log"' \
    -e '"s|./run_WPS.sh|./run_WPS_test.sh|"' \
    -e '"s|./run_WRF.sh|./run_WRF_test.sh|"' \
    -e '"s|./run_WRFDA.sh|./run_WRFDA_test.sh|"' \
    -e '"s|Using production observations|Using production observations from main DA_input directory|"' \
    -e '"s|./verification.sh|./verification_test.sh|g"' \
    $BASE/scripts/control_run_WRF.sh '>' $TEST_BASE/scripts/control_run_WRF_test.sh

# Add GEN_BE forecast saving after WRF run
cat >> $TEST_BASE/scripts/control_run_WRF_test.sh << 'GENBE_APPEND'

# Save forecasts for GEN_BE if enabled
if [ "$SAVE_GENBE_FORECASTS" = "true" ]; then
    echo "Saving forecasts for GEN_BE..." >> ${TEST_BASE_DIR}/logs/main.log
    ./save_genbe_forecasts.sh $year $month $day $hour >> ${TEST_BASE_DIR}/logs/main.log 2>&1
    if [ $? -eq 0 ]; then
        echo "GEN_BE forecasts saved successfully" >> ${TEST_BASE_DIR}/logs/main.log
    else
        echo "WARNING: Failed to save GEN_BE forecasts" >> ${TEST_BASE_DIR}/logs/main.log
    fi
fi
GENBE_APPEND

# Create run_WPS_test.sh
eval sed $COMMON_SUBS $CPU_SUBS \
    -e '"s|WRF Preprocessing|WRF_test Preprocessing|"' \
    -e '"s|WRF_test run directory created|WRF_test run directory created (testing configuration)|"' \
    -e '"s|DOMAIN_FILE=\"\${MAIN_DIR}/domain.txt\"|DOMAIN_FILE=\"$BASE/scripts/domain.txt\"|"' \
    $BASE/scripts/run_WPS.sh '>' $TEST_BASE/scripts/run_WPS_test.sh

# Create run_WRF_test.sh
eval sed $COMMON_SUBS $CPU_SUBS \
    -e '"s|WRF Model Automation Script|WRF_test Model Script|"' \
    -e '"s|^# ===============================================$|# Purpose: Test new features and configurations\n# ===============================================|"' \
    -e '"s|./run_WRFDA.sh|./run_WRFDA_test.sh|"' \
    -e '"s|Ready to set up WRF|Ready to set up WRF_test|"' \
    -e '"s|Running model without|Running WRF_test model without|"' \
    -e '"s|DOMAIN_FILE=\"\${MAIN_DIR}/domain.txt\"|DOMAIN_FILE=\"$BASE/scripts/domain.txt\"|"' \
    $BASE/scripts/run_WRF.sh '>' $TEST_BASE/scripts/run_WRF_test.sh

# Create run_WRFDA_test.sh
eval sed $COMMON_SUBS $CPU_SUBS \
    -e '"s|WRF Data Assimilation|WRF_test Data Assimilation|"' \
    -e '"s|^# ===============================================$|# Purpose: Test DA modifications and new observation types\n# ===============================================|"' \
    -e '"s|Starting WRF Data|Starting WRF_test Data|"' \
    -e '"s|DOMAIN_FILE=\"\${MAIN_DIR}/domain.txt\"|DOMAIN_FILE=\"$BASE/scripts/domain.txt\"|"' \
    $BASE/scripts/run_WRFDA.sh '>' $TEST_BASE/scripts/run_WRFDA_test.sh

# Create get_obs_test.sh if source exists
[ -f "$BASE/scripts/get_obs.sh" ] && eval sed $COMMON_SUBS \
    -e '"s|Download observations for WRF DA|Download observations for WRF_test DA|"' \
    $BASE/scripts/get_obs.sh '>' $TEST_BASE/scripts/get_obs_test.sh

# Copy additional files to WRF_test
[ -f "$BASE/scripts/save_genbe_forecasts.sh" ] && mv $BASE/scripts/save_genbe_forecasts.sh $TEST_BASE/scripts/
[ -f "$BASE/scripts/setup_genbe_wrapper.sh" ] && mv $BASE/scripts/setup_genbe_wrapper.sh $TEST_BASE/scripts/
[ -f "$BASE/scripts/convert_to_little_r.py" ] && cp $BASE/scripts/convert_to_little_r.py $TEST_BASE/scripts/
[ -f "$BASE/scripts/verification_test.sh" ] && mv $BASE/scripts/verification_test.sh $TEST_BASE/scripts/
[ -f "$BASE/scripts/parse_namelist_wps.py" ] && cp $BASE/scripts/parse_namelist_wps.py $TEST_BASE/scripts/

chmod -R +x $TEST_BASE/scripts/
echo "✅ WRF_test scripts created successfully"

echo "Copying verification R scripts into the Verification directory..."
rsync -av --exclude='app.R' "$GIT_REPO/Verification_scripts/" "$BASE/Verification/scripts/"

# Update paths in R verification scripts
echo "Updating paths in R verification scripts..."
for r_script in $BASE/Verification/scripts/*.R; do
    # Replace all occurrences of default WRF path with the actual BASE path
    sed -i "s|/wrf/WRF_Model|$BASE|g" "$r_script"
done

echo "✅ Verification scripts configured successfully"

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

time_00=$(adjust_crontab_time 6)
time_06=$(adjust_crontab_time 12)
time_12=$(adjust_crontab_time 18)
time_18=$(adjust_crontab_time 00)

echo "Adjusted crontab job start times, cycle 00: $time_00:00, cycle 06: $time_06:00, cycle 12: $time_12:00, cycle 18: $time_18:00"

# Update the crontab template with all replacements at once
echo "Updating crontab settings in $BASE/scripts/crontab_template"
sed -i "s|#30 \* \* \* \* /home/wrf/WRF_Model/scripts/clean_wrf.sh|#30 \* \* \* \* $BASE/scripts/clean_wrf.sh|" "$BASE/scripts/crontab_template"
sed -i "s|#30 5 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 00 > /home/wrf/WRF_Model/logs/runlog_00.log|#0 $time_00 \* \* \* $BASE/scripts/control_run_WRF.sh 00 > $BASE/logs/runlog_00.log|" "$BASE/scripts/crontab_template"
sed -i "s|#30 11 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 06 > /home/wrf/WRF_Model/logs/runlog_06.log|#0 $time_06 \* \* \* $BASE/scripts/control_run_WRF.sh 06 > $BASE/logs/runlog_06.log|" "$BASE/scripts/crontab_template"
sed -i "s|#30 17 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 12 > /home/wrf/WRF_Model/logs/runlog_12.log|#0 $time_12 \* \* \* $BASE/scripts/control_run_WRF.sh 12 > $BASE/logs/runlog_12.log|" "$BASE/scripts/crontab_template"
sed -i "s|#30 23 \* \* \* /home/wrf/WRF_Model/scripts/control_run_WRF.sh 18 > /home/wrf/WRF_Model/logs/runlog_18.log|#0 $time_18 \* \* \* $BASE/scripts/control_run_WRF.sh 18 > $BASE/logs/runlog_18.log|" "$BASE/scripts/crontab_template"

# Calculate WRF_test crontab times (runs at 00 and 12 UTC only)
time_test_00=$(adjust_crontab_time 6)
time_test_12=$(adjust_crontab_time 18) 
sed -i "s|#0 6 \* \* \* /home/wrf/WRF_test/scripts/control_run_WRF_test.sh 00|#0 $time_test_00 \* \* \* $TEST_BASE/scripts/control_run_WRF_test.sh 00|" "$BASE/scripts/crontab_template"
sed -i "s|#0 18 \* \* \* /home/wrf/WRF_test/scripts/control_run_WRF_test.sh 12|#0 $time_test_12 \* \* \* $TEST_BASE/scripts/control_run_WRF_test.sh 12|" "$BASE/scripts/crontab_template"
sed -i "s|/home/wrf/WRF_test/logs/runlog_00.log|$TEST_BASE/logs/runlog_00.log|" "$BASE/scripts/crontab_template"
sed -i "s|/home/wrf/WRF_test/logs/runlog_12.log|$TEST_BASE/logs/runlog_12.log|" "$BASE/scripts/crontab_template"

crontab $BASE/scripts/crontab_template

echo "Crontab for WRF set up successfully but run commands are not active by default."
echo "Remember to activate them by running 'crontab -e' and uncommenting the lines."

# Set up git repository to track configuration and scripts
setup_git_repository

# Print summary of installation
echo "
===============================================================================
                      WRF INSTALLATION COMPLETED SUCCESSFULLY
===============================================================================

📋 Installation Summary:
- WRF, WPS, WRFDA, UPP installed in: $BASE
- Production run scripts: $BASE/scripts
- Test run scripts: $TEST_BASE/scripts
- Log files will be stored in: $BASE/logs and $TEST_BASE/logs
- Installation logs in: $BASE/install_logs
- Cron jobs set up for WRF runs
- Geographical dataset in: $BASE/WPS_GEOG
- SmartMet server IP: $SMARTMET_IP
- Verification tools: $([ "$INSTALL_VERIFICATION" = true ] && echo "Installed" || echo "Not installed")$([ "$INSTALL_VERIFICATION" = true ] && echo "
- WRF verification and visualization app portal : http://localhost:3838/")

🔍 POST-INSTALLATION CHECKLIST (what needs to be done manually):
1. Define your domain:
   - Create your domain with WRF Domain Wizard (https://wrfdomainwizard.net/)
   - Save the namelist.wps file as domain.txt in $BASE/scripts/
   - The scripts will automatically read all domain settings from this file
   - Create new git commit to track domain.txt changes 

2. Set up SSH keys for SmartMet server (if using):
   - Generate SSH keys: ssh-keygen
   - Copy keys to SmartMet: ssh-copy-id smartmet@$SMARTMET_IP
   - Make sure SmartMet server is sending GFS data to the WRF server (ssh key on both sides)

3. WRF_test suite:
   - WRF_test is pre-configured for GEN_BE (DA OFF, 24h forecasts)
   - Runs at 00Z and 12Z, automatically saves 12h/24h forecasts
   - After collecting ≥30 days of data, run: $TEST_BASE/scripts/setup_genbe_wrapper.sh
   - Generated BE file replaces default be.dat for domain-specific statistics

4. Create station list $BASE/Verification/Data/Static/stationlist.csv
    - List all stations to be used in verification
    - File headers: SID,lat,lon,elev,name

5. Finalize observation preprocessing script $BASE/scripts/process_local_obs_$COUNTRY.sh
    - Fetch your input data and convert to csv format as needed.

6. Set up the cron jobs for automation:
   - Run 'crontab -e' to edit your crontab
   - Uncomment production WRF runs (4x daily: 00, 06, 12, 18 UTC)
   - Uncomment WRF test runs (2x daily: 00, 12 UTC)

===============================================================================
"

# Clean up sudo rights
sudo rm -f /etc/sudoers.d/temp_wrf_install

# Calculate and display total runtime
end_time=$(date +%s)
runtime=$((end_time - start_time))
hours=$((runtime / 3600))
minutes=$(( (runtime % 3600) / 60 ))
seconds=$((runtime % 60))

echo "Installation finished at $(date)"
echo "🕒 WRF Installation completed in ${hours}h ${minutes}m ${seconds}s"

