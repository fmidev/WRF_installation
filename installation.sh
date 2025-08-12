#!/bin/bash

# Package version configuration
# Change these values to upgrade to newer versions
# Core components
export WRF_VERSION="4.7.0"
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

# RStudio tools
export RSTUDIO_SERVER_VERSION="2024.12.1-563"
export RSTUDIO_DESKTOP_VERSION="2024.12.1-563"

export GIT_REPO=$(pwd)

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
    mkdir -p "$GIT_REPO/Run_scripts/process_local_obs"
    cat > "$GIT_REPO/Run_scripts/process_local_obs/process_local_obs_${COUNTRY}.sh" << EOF
#!/bin/bash
# ===============================================
# Process local observations for WRF DA and verification in $COUNTRY
# Author: 
# Date: 
# ===============================================

# Check for required arguments
if [ "$#" -lt 5 ]; then
    echo "Usage: $0 YYYY MM DD HH DA_DIR BASE_DIR"
    exit 1
fi

# Input variables
YYYY=$1  # Year
MM=$2    # Month
DD=$3    # Day
HH=$4    # Hour
DA_DIR=$5
BASE_DIR=$6

##CODE HERE

exit 0
EOF
    chmod +x "$GIT_REPO/Run_scripts/process_local_obs/process_local_obs_${COUNTRY}.sh"
    echo "Created template: Run_scripts/process_local_obs/process_local_obs_${COUNTRY}.sh"
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




# Create necessary directories
echo "Creating directory structure..."
mkdir -p $BASE/{libraries,WPS_GEOG,scripts,tmp,out,logs,install_logs,GFS,GEN_BE,CRTM_coef,DA_input/{be,ob/{raw_obs,obsproc},rc,varbc},Verification/{scripts,Data/{Forecast,Obs,Static},Results,SQlite_tables}}

# Install required system packages
echo "Installing required packages..."
sudo dnf config-manager --set-enabled crb
sudo dnf makecache -y -q
sudo dnf install -y epel-release gcc gfortran g++ emacs wget tar perl libxml2-devel \
    m4 chrony libcurl-devel csh ksh rsync cmake
sudo dnf update -y

# Install verification-related system packages
sudo dnf install -y htop jasper-devel eccodes eccodes-devel proj proj-devel netcdf-devel sqlite sqlite-devel R nco

# Install RStudio and Shiny server (only if verification tools are requested)
if [ "$INSTALL_VERIFICATION" = true ]; then

    echo "Installing RStudio and Shiny server..."
    cd $BASE/tmp
    wget https://download2.rstudio.org/server/rhel8/x86_64/rstudio-server-rhel-${RSTUDIO_SERVER_VERSION}-x86_64.rpm
    wget https://download1.rstudio.org/electron/rhel9/x86_64/rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm
    wget https://download3.rstudio.org/centos8/x86_64/shiny-server-1.5.23.1030-x86_64.rpm
    sudo dnf install -y rstudio-server-rhel-${RSTUDIO_SERVER_VERSION}-x86_64.rpm
    sudo dnf install -y rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm
    sudo dnf install -y shiny-server-1.5.23.1030-x86_64.rpm

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
EOF

    echo "Installing R packages for verification..."
    Rscript $BASE/tmp/install_r_packages.R > $BASE/install_logs/install_r_packages.log 2>&1

    rm -f $BASE/tmp/rstudio-server-rhel-${RSTUDIO_SERVER_VERSION}-x86_64.rpm
    rm -f $BASE/tmp/rstudio-${RSTUDIO_DESKTOP_VERSION}-x86_64.rpm
    rm -f $BASE/tmp/install_r_packages.R

    echo "R packages for verification installed successfully."
    echo "Your GitHub token has been saved to ~/.Renviron"

    # --- CONTINUE WITH SHINY APP DEPLOYMENT AND CONFIGURATION ---
    sudo mkdir /srv/shiny-server/harpvis
    sudo chown -R shiny:shiny /srv/shiny-server/harpvis

    echo "Deploying harpVis Shiny app..."
    sudo cp $GIT_REPO/Verification_scripts/app.R /srv/shiny-server/harpvis/

EOF

    sudo chown shiny:shiny /srv/shiny-server/harpvis/app.R
    sudo chmod 644 /srv/shiny-server/harpvis/app.R

    echo "harpVis Shiny app deployed successfully."
    echo "Setting up Shiny user environment and permissions..."
    sudo echo "R_LIBS_USER=/home/$USER/R/x86_64-redhat-linux-gnu-library/4.5" | sudo tee -a /home/shiny/.Renviron
    sudo chown shiny:shiny /home/shiny/.Renviron
    sudo setfacl -m u:shiny:rx /home/$USER
    sudo setfacl -R -m u:shiny:rx /home/$USER/R
    
    echo "Restarting Shiny server..."
    sudo systemctl restart shiny-server
    sudo systemctl enable shiny-server
    echo "Shiny server configured to use R packages from: $USER_R_LIB"


fi

# Detect number of CPU cores and save one less for parallel processes
CPU_COUNT=$(nproc)
MAX_CPU=$((CPU_COUNT - 1))
if [ $MAX_CPU -lt 1 ]; then
    MAX_CPU=1
fi
echo "Detected $CPU_COUNT CPU cores, will use maximum of $MAX_CPU for parallel processes"

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

# Setup UPP more efficiently
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
    sed -i "s|export RUN_COMMAND=.*|export RUN_COMMAND=\"mpirun -np ${MAX_CPU} \${POSTEXEC}/unipost.exe \"|" "$UNIPOST"
    sed -i "s|ln -fs \${DOMAINPATH}/parm/post_avblflds_comm.xml post_avblflds.xml|ln -fs \${UNIPOST_HOME}/parm/post_avblflds.xml post_avblflds.xml|" "$UNIPOST"
    sed -i "s|ln -fs \${DOMAINPATH}/parm/params_grib2_tbl_new params_grib2_tbl_new|ln -fs \${UNIPOST_HOME}/parm/params_grib2_tbl_new params_grib2_tbl_new|" "$UNIPOST"

    echo "✅ UPP setup completed successfully."
else
    echo "❌ UPP is not installed. Skipping UPP setup..."
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
    tar -zxvf geog_complete.tar.gz --strip-components=1
    tar -zxvf geog_high_res_mandatory.tar.gz --strip-components=1
    echo "Geographical dataset downloaded and extracted successfully."
else
    echo "Geographical dataset already exists. Skipping..."
fi

# Copy and update scripts
echo "Copying run scripts into the scripts directory..."
cp -r $GIT_REPO/Run_scripts/* $BASE/scripts/
chmod -R +x $BASE/scripts/

echo "Copying verification R scripts into the Verification directory..."
cp $GIT_REPO/Verification_scripts/* $BASE/Verification/scripts/

# Update paths in R verification scripts
echo "Updating paths in R verification scripts..."
for r_script in $BASE/Verification/scripts/*.R; do
    # Replace all occurrences of default WRF path with the actual BASE path
    sed -i "s|/wrf/WRF_Model|$BASE|g" "$r_script"
done

# Update SmartMet IP address
echo "Updating configuration in run scripts..."
sed -i "s|smartmet@ip-address|smartmet@$SMARTMET_IP|g" $BASE/scripts/control_run_WRF.sh

# Add CPU cores and BASE_DIR into env.sh
sed -i "s|^export BASE_DIR=.*|export BASE_DIR=$BASE|" "$BASE/scripts/env.sh"
sed -i "s|^export MAX_CPU=.*|export MAX_CPU=$MAX_CPU|" "$BASE/scripts/env.sh"
sed -i "s|^export COUNTRY=.*|export COUNTRY=\"$COUNTRY\"|" "$BASE/scripts/env.sh"

# Update all script paths
for script in control_run_WRF.sh run_WRF.sh execute_upp.sh run_WRFDA.sh clean_wrf.sh get_obs.sh verification.sh; do
    sed -i "s|^source .*|source $BASE/scripts/env.sh|" "$BASE/scripts/$script"
done

# Set up git repository to track configuration and scripts
setup_git_repository

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

crontab $BASE/scripts/crontab_template

echo "Crontab for WRF set up successfully but run commands are not active by default."
echo "Remember to activate them by running 'crontab -e' and uncommenting the lines."

# Install verification tools
echo "Checking if system is compatible for verification tools installation..."

# Print summary of installation
echo "
===============================================================================
                      WRF INSTALLATION COMPLETED SUCCESSFULLY
===============================================================================

📋 Installation Summary:
- WRF, WPS, WRFDA, UPP installed in: $BASE
- Run scripts are in: $BASE/scripts
- Log files will be stored in: $BASE/logs
- Installation logs in: $BASE/install_logs
- Cron jobs set up for WRF runs
- Geographical dataset in: $BASE/WPS_GEOG
- SmartMet server IP: $SMARTMET_IP
- Verification tools: $([ "$INSTALL_VERIFICATION" = true ] && echo "Installed" || echo "Not installed")$([ "$INSTALL_VERIFICATION" = true ] && echo "
- harpVis app available at: http://localhost:3838/harpvis/" || echo "")

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

