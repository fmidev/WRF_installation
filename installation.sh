#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define base directory
export BASE=/home/$USER/WRF_Model
export GIT_REPO=$(pwd)

# Install required GNU compilers and utilities
echo "Installing required packages..."
sudo dnf install -y gcc gfortran g++ htop emacs wget tar perl libxml2-devel m4 chrony libcurl-devel csh ksh git rsync

# Create necessary directories
echo "Creating directory structure..."
mkdir -p $BASE/{libraries,WPS_GEOG,scripts,tmp,out,logs,GFS,GEN_BE,CRTM_coef,DA_input/{be,ob/{raw_obs,obsproc},rc,varbc},Verification/{scripts,Data/{Forecast,Obs,Static},Results,SQlite_tables}}

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
    local dir_name=$2
    local configure_args=$3
    local file_name=${url##*/}

    if [ -d "$BASE/libraries/$dir_name/install" ] && [ "$(ls -A $BASE/libraries/$dir_name/install)" ]; then
        echo "$dir_name is already installed. Skipping..."
        return
    fi

    echo "Installing $dir_name..."
    cd $BASE/libraries

    # Check if the file is already downloaded
    if [ ! -f "$file_name" ]; then
        echo "Downloading $file_name..."
        wget $url
    else
        echo "$file_name already exists. Skipping download..."
    fi

    # Extract the file
    if [[ $file_name == *.zip ]]; then
        unzip -o $file_name
    else
        tar -zxvf $file_name
    fi

    cd $dir_name
    if [ $dir_name == "netcdf-fortran-4.6.1" ]; then
        eval ./configure --prefix=$BASE/libraries/netcdf-c-4.9.2/install $configure_args
    else
        mkdir -p install
        eval ./configure --prefix=$BASE/libraries/$dir_name/install $configure_args
    fi
    make
    make install
}

# Set compilers explicitly
export CC=gcc
export CXX=g++
export FC=gfortran

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

# Install WRF
if [ ! -d "$BASE/WRF" ]; then
    echo "Installing WRF..."
    cd $BASE
    wget https://github.com/wrf-model/WRF/releases/download/v4.6.1/v4.6.1.tar.gz
    tar -zxvf v4.6.1.tar.gz
    mv WRFV4.6.1 WRF
    cd WRF
    export WRF_EM_CORE=1
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5-1.14.4-3/install/
    export jasper=$BASE/libraries/jasper-1.900.1/install/
    export JASPERLIB=$BASE/libraries/jasper-1.900.1/install/lib
    export JASPERINC=$BASE/libraries/jasper-1.900.1/install/include
    export WRF_DA_CORE=0
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    echo "Configuring WRF..."
    echo 34 | ./configure # Automatically select dmpar with GNU compilers
    echo "Compiling WRF... (output written into compile.log)"
    ./compile em_real >& compile.log
    check_compile_log "compile.log"
else
    echo "WRF is already installed. Skipping..."
fi

# Install WPS
if [ ! -d "$BASE/WPS" ]; then
    echo "Installing WPS..."
    cd $BASE
    wget https://github.com/wrf-model/WPS/archive/refs/tags/v4.6.0.tar.gz
    tar -zxvf v4.6.0.tar.gz
    mv WPS-4.6.0/ WPS
    cd WPS
    export jasper=$BASE/libraries/jasper-1.900.1/install/
    export JASPERLIB=$BASE/libraries/jasper-1.900.1/install/lib
    export JASPERINC=$BASE/libraries/jasper-1.900.1/install/include
    export WRF_DIR=$BASE/WRF
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    echo "Configuring WPS..."
    echo 3 | ./configure # Automatically select dmpar with GNU compilers
    sed -i '/COMPRESSION_LIBS/s|=.*|= -L${BASE}/libraries/jasper-1.900.1/install/lib -L${BASE}/libraries/libpng-1.6.43/install/lib -L${BASE}/libraries/zlib-1.3.1/install/lib -ljasper -lpng -lz|' configure.wps
    sed -i '/COMPRESSION_INC/s|=.*|= -I${BASE}/libraries/jasper-1.900.1/install/include -I${BASE}/libraries/libpng-1.6.43/install/include -I${BASE}/libraries/zlib-1.3.1/install/include|' configure.wps
    echo "Compiling WPS... (output written into compile.log)"
    ./compile >& compile.log
    check_compile_log "compile.log"
else
    echo "WPS is already installed. Skipping..."
fi


# Install WRFDA
if [ ! -d "$BASE/WRFDA" ]; then
    echo "Installing WRFDA..."
    cd $BASE
    tar -zxvf v4.6.1.tar.gz
    mv WRFV4.6.1/ WRFDA
    cd WRFDA
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5-1.14.4-3/install/
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    export WRFPLUS_DIR=$BASE/WRFPLUS/
    echo "Configuring WRFDA..."
    echo 34 | ./configure wrfda # Automatically select dmpar with GNU compilers
    echo "Compiling WRFDA... (output written into compile.log)"
    ./compile -j 10 all_wrfvar >& compile.log
    check_compile_log "compile.log"
else
    echo "WRFDA is already installed. Skipping..."
fi

# Install NCEPlibs
if [ ! -d "$BASE/libraries/NCEPlibs" ]; then
    echo "Installing NCEPlibs..."
    cd $BASE/libraries/
    git clone https://github.com/NCAR/NCEPlibs.git
    cd NCEPlibs
    mkdir -p install
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export PNG_INC=$BASE/libraries/libpng-1.6.43/install/include/
    export JASPER_INC=$BASE/libraries/jasper-1.900.1/install/include/
    sed -i '/FFLAGS/s|$| -fallow-argument-mismatch -fallow-invalid-boz|' macros.make.linux.gnu
    echo "Compiling NCEPlibs..."
    echo y | ./make_ncep_libs.sh -s linux -c gnu -d $BASE/libraries/NCEPlibs/install/ -o 0 -m 1 -a upp
else
    echo "NCEPlibs is already installed. Skipping..."
fi

# Install UPP
if [ ! -d "$BASE/UPP" ]; then
    echo "Installing UPP..."
    cd $BASE
    git clone -b dtc_post_v4.1.0 --recurse-submodules https://github.com/NOAA-EMC/EMC_post UPPV4.1
    mv UPPV4.1 UPP
    cd UPP
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NCEPLIBS_DIR=$BASE/libraries/NCEPlibs/install/
    echo "Configuring UPP... (output written into compile.log)"
    echo 8 | ./configure # Automatically select gfortran dmpar
    sed -i '/FFLAGS/s|$| -fallow-argument-mismatch -fallow-invalid-boz|' configure
    echo "Compiling UPP..."
    ./compile >& compile.log
    check_compile_log "compile.log"
else
    echo "UPP is already installed. Skipping..."
fi

# Setup UPP
if [ -d "$BASE/UPP" ]; then
    echo "Setting up UPP..."
    mkdir -p $BASE/{UPP_out,UPP_wrk/{parm,postprd,wrprd}}
    cp $BASE/UPP/scripts/run_unipost $BASE/UPP_wrk/postprd/
    cp $BASE/UPP/parm/wrf_cntrl.parm $BASE/UPP_wrk/parm/ # for grib1
    cp $BASE/UPP/parm/postxconfig-NT-WRF.txt $BASE/UPP_wrk/parm/ # for grib2 (default)

    # Edit run_unipost script with appropriate paths and variables
    sed -i "s|export TOP_DIR=.*|export TOP_DIR=$BASE|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export DOMAINPATH=.*|export DOMAINPATH=$BASE/UPP_wrk|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export UNIPOST_HOME=.*|export UNIPOST_HOME=\${TOP_DIR}/UPP|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export POSTEXEC=.*|export POSTEXEC=\${UNIPOST_HOME}/exec|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export SCRIPTS=.*|export SCRIPTS=\${UNIPOST_HOME}/scripts|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export modelDataPath=.*|export modelDataPath=\${DOMAINPATH}/wrfprd|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export paramFile=.*|export paramFile=\${DOMAINPATH}/parm/wrf_cntrl.parm|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export txtCntrlFile=.*|export txtCntrlFile=\${DOMAINPATH}/parm/postxconfig-NT-WRF.txt|" $BASE/UPP_wrk/postprd/run_unipost

    sed -i "s|export dyncore=.*|export dyncore=\"ARW\"|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export inFormat=.*|export inFormat=\"netcdf\"|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export outFormat=.*|export outFormat=\"grib2\"|" $BASE/UPP_wrk/postprd/run_unipost
    
    sed -i "s|export startdate=.*|export startdate=2024070800|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export fhr=.*|export fhr=00|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export lastfhr=.*|export lastfhr=72|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export incrementhr=.*|export incrementhr=01|" $BASE/UPP_wrk/postprd/run_unipost
    
    sed -i "s|export domain_list=.*|export domain_list=\"d01 d02\"|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|export RUN_COMMAND=.*|export RUN_COMMAND=\"mpirun -np 10 \${POSTEXEC}/unipost.exe \"|" $BASE/UPP_wrk/postprd/run_unipost

    sed -i "s|ln -fs \${DOMAINPATH}/parm/post_avblflds_comm.xml post_avblflds.xml|ln -fs \${UNIPOST_HOME}/parm/post_avblflds_comm.xml post_avblflds.xml|" $BASE/UPP_wrk/postprd/run_unipost
    sed -i "s|ln -fs \${DOMAINPATH}/parm/params_grib2_tbl_new params_grib2_tbl_new|ln -fs \${UNIPOST_HOME}/parm/params_grib2_tbl_new params_grib2_tbl_new|" $BASE/UPP_wrk/postprd/run_unipost

    echo "UPP setup completed successfully."
else
    echo "UPP is not installed. Skipping UPP setup..."
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
        wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz
    else
        echo "geog_complete.tar.gz already exists. Skipping download..."
    fi

    if [ ! -f "geog_high_res_mandatory.tar.gz" ]; then
        wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz
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

# Copy run scripts into the scripts directory
echo "Copying run scripts into the scripts directory..."
cp $GIT_REPO/Run_scripts/* $BASE/scripts/
chmod +x $BASE/scripts/*
echo "Run scripts copied and made executable successfully."

# Place crontab_wrf template into the system crontab
echo "Setting up crontab for WRF..."
crontab $BASE/scripts/crontab_template
echo "Crontab for WRF set up successfully."

echo "Installation completed successfully!"
