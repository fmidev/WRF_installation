####################################
# Read_forecast and save to SQLite #
####################################

args = commandArgs(trailingOnly=TRUE)
if (length(args) != 1){
  stop("Give forecast date/time as input argument in yyyymmddHH format, E.g. Rscript read_forecast_wrf_d02.R 2024010100")
}

datetime = args[1] 
if (nchar(datetime) != 10){
  stop("Give forecast date/time as input argument in yyyymmddHH format, E.g. Rscript read_forecast_wrf_d02.R 2024010100")
}

library(harp)

#Now we use stations from NCHM provided file
station_list <- read.csv("/home/wrf/WRF_Model/Verification/Data/Static/stationlist.csv")
file_path = "/home/wrf/WRF_Model/Verification/Data/Forecast/" #parent path to forecast files
template <- "{fcst_model}_{YYYY}{MM}{DD}{HH}" #show_file_templates()
sql_folder <- "/home/wrf/WRF_Model/Verification/SQlite_tables/FCtables" # where to save sqlite tables

cat("Processing forecast for date:", datetime, "\n")
cat("Using model: wrf_d02\n")

wrf_point <- read_forecast(
  dttm           = datetime,
  fcst_model     = "wrf_d02",
  parameter      = c("T2m","WS10m","Pcp","Pressure","Q2"), #show_param_defs("wrf")
  file_format    = "netcdf",
  file_format_opts = netcdf_opts("wrf"),
  lead_time      = seq(0, 72, 1),
  transformation = "interpolate",
  transformation_opts = interpolate_opts(
    stations = station_list,
    method = "bilinear",
    clim_param = "topo", #parameter for topography 
    correct_t2m = TRUE  
  ),
  file_path      = file_path,
  file_template  = template,
  output_file_opts = sqlite_opts(
    path = sql_folder,
    template = "fctable_det", #show_file_templates(5)
    index_cols = c("fcst_dttm", "lead_time", "SID"),
    remove_model_elev = TRUE), 
  return_data    = FALSE #usually FALSE
)

cat("Forecast processing completed for wrf_d02\n")



