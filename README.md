# WRF installation 
This repository provides documentation on how to compile and install the WRF model, along with the necessary tools. It also outlines the workflow and explains how to set it up for automated, operational model runs. If you are testing WRF on your own computer, check how many CPUs are available. While the model can run on a single core, these instructions are intended for parallel computation. Also, ensure you have sufficient disk space - static geographical data requires approximately 100GB, and the model input/output/temporary files take up a similar amount, depending on your domain. For testing, 200-300GB should be sufficient, while around 1TB is recommended for operational runs. More comprehensive documentation about WRF model can be found [here](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/index.html) 

## Downloading of libraries and compiling of source code
The text file `installation` provides a step-by-step guide on how to install and compile all the needed libraries. Similar instructions are also provided for the WRF source code and its pre/post-processing tools. Following these instructions will ensure that all the necessary binaries for running the WRF model are installed correctly. When running the WRF model or its tools, it is necessary to define some environment variables. These are controlled by `env.sh` which is executed within the model run scripts. Note that in paths (both in installation and `env.sh`), `user` has to be replaced with the correct username. Be also sure that all needed programs were installed, like rsync, etc. (List available in beginning of installation instruction.)

## Domain maker
Desired domains for WRF can be easily drawn with [WRF Domain Wizard](https://wrfdomainwizard.net/).

1. Select option "New" from the sidebar and draw the domain on the map. Keep in mind that this will be the outermost domain, which will be calculated with a resolution based on dx/dy (default 12 km).
2. Once you're done, add an inner domain by clicking "Add Nest" and modify it on map.
3. Adjust the resolution of the inner domain by using the "Parent_grid_ratio" setting. The default value is 3, which corresponds to a resolution of 4 km (12 km / 3).
4. To download the finalized domain namelist (namelist.wps) for WRF, click "Save". The information is needed later when configuring WPS running scripts.

## Work flow

### Boundaries
WRF requires boundary files in GRIB format. The script `Download_GFS/get_gfs.sh` is used to download GFS data to the WRF server. The configuration file `Download_GFS/gfs.cnf` specifies the desired GFS area, resolution, valid hours, and other parameters for the download. The paths may need adjustment to work correctly for the specific case. The key is to place the GFS data in the directory specified in the running scripts (default `/home/{user}/WRF_Model/GFS`). Script is always downloading the most recent boundaries.

```
./get_gfs.sh
```

### Preprosessing
In order to use preprocessing tool WPS, a static geographical dataset needs to be downloaded. 
```
wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_complete.tar.gz /path/to/WPS_GEOG/
wget https://www2.mmm.ucar.edu/wrf/src/wps_files/geog_high_res_mandatory.tar.gz /path/to/WPS_GEOG/ 
tar -zxvf geog_complete.tar.gz --strip-components=1
tar -zxvf geog_high_res_mandatory.tar.gz --strip-components=1
```

The next phase involves editing the namelist options in `Run_scripts/Run_WPS.sh`. Update the parameters based on the `namelist.wps` file generated by the WRF Domain Wizard, focusing mainly on domain-related variables, especially those within the geogrid section. Other parameters can be modified as well, but it's important to understand their function. You can find detailed information about the various namelist options in this [link](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/wps.html#wps-namelist-variables).

After setting up the namelist parameters, it is necessary to go through the script and modify every path to correspond with the installation and data directories. The WPS run script launches executables in parallel using the mpirun command, so it is important to set the correct number of cores. For example, the command `mpirun -np 24 program.exe` uses 24 CPUs.

WPS setup can be tested from command line by running:
```
./Run_WPS.sh <year> <month> <day> <hour> <leadtime> <prod_dir>
./Run_WPS.sh 2024 09 10 01 00 48 /home/{user}/WRF_Model/out/ 
```
If the script runs successfully, all the necessary input data for the WRF model run should be ready.

### Observations (optional)
Observations are essential for data assimilation and verification. Currently, the `get_obs.sh` script gathers observations (primarily satellite radiances) available from the [NCEP real-time data](https://nomads.ncep.noaa.gov/pub/data/nccf/com/obsproc/prod/). The script does not yet support radar or local synoptic observations, as these raw observations need to be processed first into the Little_R format. 

The usage of the script is as follows:
```
./get_obs $year $month $day $hour
```
Note that NCEP real-time data archive only includes the most recent couple of days.

### The model
The `Run_WRF.sh` script automates the preparation, execution, and optional data assimilation (WRFDA) for WRF model simulations. It is important to review the configuration and ensure that every path in the script is correct. Additionally, the namelist variables must be updated to correspond to the variables in the WPS namelist. For other changes in the namelist, refer to this [site](https://www2.mmm.ucar.edu/wrf/users/wrf_users_guide/build/html/namelist_variables.html)

To execute the script, provide the required arguments:
```
./Run_WRF.sh <year> <month> <day> <hour> <leadtime> <prod_dir>
```
Enable data assimilation (DA) by setting `WRFDA=true` in the `env.sh` file. WRFDA namelist variables can also be modified within the same `Run_WRF.sh` script. For DA, it is essential to download CRTM coefficients for satellite assimilation. Additionally, background error (BE) must be calculated or a generic BE can be used from the WRFDA source code. Below is an example of how to download coefficients and use the generic BE.

CRTM:
```
mkdir -p /home/wrf/WRF_Model/CRTM_coef
cd /home/wrf/WRF_Model/CRTM_coef
wget https://www2.mmm.ucar.edu/wrf/users/wrfda/download/crtm_coeffs_2.3.0.tar.gz 
tar -xvf crtm_coeffs_2.3.0.tar.gz
```
BE:
```
cp -p $WRFDA_DIR/var/run/be.dat.cv3 $WORK_DIR_DA/be.dat
```

### Postprocessing
Unified Post Processor (UPP) can be used to convert WRF NetCDF output to Grib. Instructions how to compile UPP can be found from the `installation`. The text file `setup_upp` describes how to setup UPP as a WRF postprosessing tool and with `Run_scripts/execute_upp.sh` the UPP can be easily used to automated NETCDF -> GRIB conversion. 

### Verification
Instruction how to use HARP verification for WRF here... (some day)

### Cleaning and automization
The `clean_wrf` script cleans GFS boundary files, WRF, and UPP output files. This can be set up as a cron job, for example, to clean the files once a day.

For an automated run, the `control_run_WRF.sh` script can be used to execute all the steps mentioned above. However, it is recommended to test each part of the workflow independently before using this control script to run WRF. The script can be executed as follows:
```
./control_run_WRF.sh <analysis_hour>
```

