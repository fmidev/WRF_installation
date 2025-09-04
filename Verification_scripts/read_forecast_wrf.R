####################################
# Read_forecast and save to SQLite #
####################################

# Parse command line arguments - expecting forecast date in format yyyymmddHH and domain (d01 or d02)
args = commandArgs(trailingOnly=TRUE)
if (length(args) != 2 || nchar(args[1]) != 10 || !(args[2] %in% c("d01", "d02"))){
  stop("Usage: Rscript read_forecast_wrf.R <yyyymmddHH> <domain>\n  Where domain is either d01 or d02\n  Example: Rscript read_forecast_wrf.R 2024010100 d01")
}
datetime = args[1]
domain = args[2]

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
fcst_model <- paste0("wrf_", domain)
forecast_file <- paste0(file_path, "/", fcst_model, "_", datetime)

# Define WRF variable names
wrf_vars <- c("T2", "U10", "V10", "RAINC", "RAINNC", "PSFC", "Q2")

cat("Processing forecast for date:", datetime, "\n")
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
    parameter = wrf_vars,
    file_format = "netcdf",
    file_format_opts = netcdf_opts(
      "wrf",
      param_find = list(
        "T2" = "T2",
        "U10" = "U10", 
        "V10" = "V10",
        "RAINC" = "RAINC",
        "RAINNC" = "RAINNC", 
        "PSFC" = "PSFC",
        "Q2" = "Q2"
      )
    ),
    lead_time = seq(0, 72, 1),
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
  cat("- Variables requested:", paste(wrf_vars, collapse=", "), "\n")
}) 
 
cat("Forecast processing completed for", fcst_model, "\n")
