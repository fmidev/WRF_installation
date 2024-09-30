# WRF_installation 
This repository provides documentation on how to compile and install the WRF model, along with the necessary tools. It also outlines the workflow and explains how to set it up for automated, operational model runs. If you are testing WRF on your own computer, check how many CPUs are available. While the model can run on a single core, these instructions are intended for parallel computation. Also, ensure you have sufficient disk space - static geographical data requires approximately 200GB, and the model input/output/temporary files take up a similar amount, depending on your domain. For testing, 300-500GB should be sufficient, while 1-2TB is recommended for operational runs.

## Downloading of libraries and compiling of source code
The text file `installation` provides a step-by-step guide on how to install and compile all the needed libraries. Similar instructions are also provided for the WRF source code and its pre/post-processing tools. Following these instructions will ensure that all the necessary binaries for running the WRF model are installed correctly. When running the WRF model or its tools, it is necessary to define some environment variables. By running `source wrf_env.sh` before executing the model, the correct variables and paths are ensured to be in place. Note that in paths, `user` has to be replaced with the correct username.

## Domain maker
Desired domains for WRF can be easily drawn with [WRF Domain Wizard](https://wrfdomainwizard.net/).

1. Select option "New" from the sidebar and draw the domain on the map. Keep in mind that this will be the outermost domain, which will be calculated with a resolution based on dx/dy (default 12 km).
2. Once you're done, add an inner domain by clicking "Add Nest" and modify it on map.
3. Adjust the resolution of the inner domain by using the "Parent_grid_ratio" setting. The default value is 3, which corresponds to a resolution of 4 km (12 km / 3).
4. To download the finalized domain namelist (namelist.wps) for WRF, click "Save". The information is needed later when configuring WPS running scripts.

## Work flow

### Boundaries
WRF requires boundary files in GRIB format. The script `Download_GFS/get_gfs.sh` is used to download GFS data to SmartMet and to copy the data to the WRF server. The configuration file `Download_GFS/gfs.cnf` specifies the desired GFS area, resolution, valid hours, and other parameters for the download. Note that the script `get_gfs.sh` also includes functionality to convert GRIB data to SQD format, but this step is commented out, as it is not needed for WRF purposes. The paths may need adjustment to work correctly for the specific case. The key is to place the GFS data in the directory specified in the running scripts (default `/home/{user}/GFS`) 
### Preprosessing
Scripts how to use WPS
### The model
Scripts for running the model, possibly DA as well 
### Postprocessing
Unified Post Processor (UPP) can be used to convert WRF NetCDF output to Grib. Instructions how to compile UPP can be found from the `installation`. The text file `setup_upp` describes how to setup UPP as a WRF postprosessing tool and with `Run_scripts/execute_upp.sh` the UPP can be easily used to automated NETCDF -> GRIB conversion.      
### Cleaning and automization
`clean_wrf` script cleans GFS boundary files, WRF and UPP output files.

