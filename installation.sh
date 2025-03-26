#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Define base directory
export BASE=/home/$USER/WRF_Model

# Install required GNU compilers and utilities
echo "Installing required packages..."
sudo dnf install -y gcc gfortran g++ htop emacs wget tar perl libxml2-devel m4 chrony libcurl-devel csh ksh git rsync

# Create necessary directories
echo "Creating directory structure..."
mkdir -p $BASE/{libraries,WPS_GEOG,scripts,tmp,out,logs,GFS,GEN_BE,CRTM_coef,DA_input/{be,ob/{raw_obs,obsproc},rc,varbc},Verification/{scripts,Data/{Forecast,Obs,Static},Results,SQlite_tables}}

# Function to check for errors in compilation logs
check_compile_log() {
    local log_file=$1
    if grep -i "error" $log_file; then
        echo "Compilation failed. Check the log file: $log_file"
        exit 1
    fi
}

# Function to download, extract, configure, and install libraries
install_library() {
    local url=$1
    local dir_name=$2
    local configure_args=$3

    if [ -d "$BASE/libraries/$dir_name/install" ] && [ "$(ls -A $BASE/libraries/$dir_name/install)" ]; then
        echo "$dir_name is already installed. Skipping..."
        return
    fi

    echo "Installing $dir_name..."
    cd $BASE/libraries
    wget $url
    if [[ $url == *.zip ]]; then
        unzip ${url##*/}
    else
        tar -zxvf ${url##*/}
    fi
    cd $dir_name
    mkdir -p install
    eval ./configure --prefix=$BASE/libraries/$dir_name/install $configure_args
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
    echo "Compiling WRF..."
    ./compile em_real >& compile.log
    check_compile_log compile.log
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
    sed -i '/COMPRESSION_LIBS/s|=.*|= -L$BASE/libraries/jasper-1.900.1/install/lib -L$BASE/libraries/libpng-1.6.43/install/lib -L$BASE/libraries/zlib-1.3.1/install/lib -ljasper -lpng -lz|' configure.wps
    sed -i '/COMPRESSION_INC/s|=.*|= -I$BASE/libraries/jasper-1.900.1/install/include -I$BASE/libraries/libpng-1.6.43/install/include -I$BASE/libraries/zlib-1.3.1/install/include|' configure.wps
    echo "Compiling WPS..."
    ./compile >& compile.log
    check_compile_log compile.log
else
    echo "WPS is already installed. Skipping..."
fi


# Install WRFDA
if [ ! -d "$BASE/WRFDA" ]; then
    echo "Installing WRFDA..."
    cd $BASE
    wget https://github.com/wrf-model/WRF/releases/download/v4.6.0/v4.6.0.tar.gz
    tar -zxvf v4.6.0.tar.gz
    mv WRFV4.6.0/ WRFDA
    cd WRFDA
    export NETCDF=$BASE/libraries/netcdf-c-4.9.2/install
    export NETCDF4=1
    export HDF5=$BASE/libraries/hdf5-1.14.4-3/install/
    export WRFIO_NCD_LARGE_FILE_SUPPORT=1
    export WRFPLUS_DIR=$BASE/WRFPLUS/
    echo "Configuring WRFDA..."
    echo 34 | ./configure wrfda # Automatically select dmpar with GNU compilers
    echo "Compiling WRFDA..."
    ./compile -j 10 all_wrfvar >& compile.log
    check_compile_log compile.log
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
    sed -i 's|^FFLAGS =|FFLAGS = -fallow-argument-mismatch -fallow-invalid-boz|' macros.make.linux.gnu
    echo "Compiling NCEPlibs..."
        ./make_ncep_libs.sh -s linux -c gnu -d $BASE/libraries/NCEPlibs/install/ -o 0 -m 1 -a upp >& compile.log
    check_compile_log compile.log
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
    echo "Configuring UPP..."
    ./configure # Automatically select gfortran dmpar
    sed -i '/FFLAGS/s|$| -fallow-argument-mismatch -fallow-invalid-boz|' configure
    echo "Compiling UPP..."
    ./compile >& compile.log
    check_compile_log compile.log
else
    echo "UPP is already installed. Skipping..."
fi

echo "Installation completed successfully!"
