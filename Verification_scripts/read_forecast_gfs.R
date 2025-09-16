####################################
# Read GFS forecast and save to SQLite #
####################################

# Parse command line arguments - expecting forecast date in format yyyymmddHH
args = commandArgs(trailingOnly=TRUE)
if (length(args) != 1 || nchar(args[1]) != 10){
  stop("Usage: Rscript read_forecast_gfs.R <yyyymmddHH>\n  Example: Rscript read_forecast_gfs.R 2024010100")
}
datetime = args[1]

# Load required libraries for forecast processing and NetCDF handling
library(harp)
library(ncdf4)

# Function to inspect NetCDF file contents and verify variables
inspect_netcdf <- function(file_path) {
  tryCatch({
    if (!file.exists(file_path)) {
      cat("File does not exist:", file_path, "\n")
      return(FALSE)
    }
    
    nc <- nc_open(file_path)
    cat("NetCDF file variables:", paste(names(nc$var), collapse=", "), "\n")
    nc_close(nc)
    return(TRUE)
  }, error = function(e) {
    cat("Error inspecting NetCDF file:", e$message, "\n")
    return(FALSE)
  })
}

# Set up paths and configuration for forecast processing
station_list <- read.csv("/wrf/WRF_Model/Verification/Data/Static/stationlist_KYR.csv")
file_path <- "/wrf/WRF_Model/Verification/Data/Forecast" 
template <- "{fcst_model}_{YYYY}{MM}{DD}{HH}"
sql_folder <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
fcst_model <- "gfs"
forecast_file <- paste0(file_path, "/", fcst_model)

# Define GFS variable names and their mapping
# These should match the variables extracted in the verification.sh script
gfs_vars <- c("TMP", "UGRD", "VGRD", "PRES", "SPFH")

cat("Processing GFS forecast for date:", datetime, "\n")
cat("Using model:", fcst_model, "\n")

# Check if forecast file exists
if (!file.exists(forecast_file)) {
  cat("ERROR: Forecast file not found:", forecast_file, "\n")
  cat("Files in directory", file_path, ":\n")
  print(list.files(file_path, pattern = fcst_model))
  stop(paste0("Forecast file not found: ", forecast_file))
}

# Inspect NetCDF file to verify variables
cat("Forecast file found! Inspecting contents...\n")
inspect_netcdf(forecast_file)

# Process and write forecast data
cat("Reading forecast data and writing to SQLite...\n")
tryCatch({
  read_forecast(
    dttm = datetime,
    fcst_model = fcst_model,
    parameter = gfs_vars,
    file_format = "netcdf",
    file_format_opts = netcdf_opts(
      "gfs",
      param_find = list(
        "T2" = "TMP",    # 2m temperature
        "U10" = "UGRD", # 10m U wind
        "V10" = "VGRD", # 10m V wind
        "PSFC" = "PRES", # Surface pressure
        "Q2" = "SPFH"   # 2m specific humidity
      )
    ),
    lead_time = seq(0, as.numeric(Sys.getenv("LEADTIME")), 1),
    transformation = "interpolate",
    transformation_opts = interpolate_opts(
      stations = station_list,
      method = "bilinear",
      clim_param = "topo"
    ),
    file_path = file_path,
    file_template = template,
    output_file_opts = sqlite_opts(
      path = sql_folder,
      template = "fctable_det",
      index_cols = c("fcst_dttm", "lead_time", "SID"),
      remove_model_elev = TRUE
    ),
    return_data = FALSE
  )
  cat("Forecast data successfully written to SQLite\n")
}, error = function(e) {
  cat("Error processing forecast:", e$message, "\n")
   
  # Additional debugging information
  cat("Detailed error diagnostics:\n")
  cat("- File path:", file_path, "\n")
  cat("- File template:", template, "\n")
  cat("- Variables requested:", paste(gfs_vars, collapse=", "), "\n")
}) 
 
cat("GFS forecast processing completed\n")