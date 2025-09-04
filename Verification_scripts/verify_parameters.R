#!/usr/bin/env Rscript
##################################################
# WRF Forecast Verification Script using harp
##################################################

# Load required libraries
suppressPackageStartupMessages({
  library(harp)
  library(dplyr)
  library(ggplot2)
  library(optparse)
})

# Argument parsing and validation
parse_and_validate_args <- function() {
  option_list <- list(
    make_option(c("-s", "--start_date"), type="character", default=NULL, 
                help="Start date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
    make_option(c("-e", "--end_date"), type="character", default=NULL, 
                help="End date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
    make_option(c("-o", "--output_dir"), type="character", default="/wrf/WRF_Model/Verification/Results", 
                help="Output directory for verification results [default= %default]")
  )
  opt <- parse_args(OptionParser(option_list=option_list))
  if (is.null(opt$start_date) || is.null(opt$end_date) ||
      nchar(opt$start_date) != 10 || nchar(opt$end_date) != 10) {
    stop("Invalid start or end date. Must be in format YYYYMMDDHH.")
  }
  opt
}

# Forecast reading
read_forecasts <- function(start_date, end_date, models, fcst_dir) {
  cat("Step 1: Reading forecasts for both domains...\n")
  fcst_t2m <- read_point_forecast(
    dttm = seq_dttm(start_date, end_date, "6h"),
    fcst_model = models,
    parameter = "T2m",
    file_path = fcst_dir,
    file_template = "{fcst_model}/{YYYY}/{MM}/FCTABLE_T2_{YYYY}{MM}_{HH}.sqlite",
    lead_time = seq(0, 72, 1)
  )
  fcst_psfc <- read_point_forecast(
    dttm = seq_dttm(start_date, end_date, "6h"),
    fcst_model = models,
    parameter = "PSFC",
    file_path = fcst_dir,
    file_template = "{fcst_model}/{YYYY}/{MM}/FCTABLE_PSFC_{YYYY}{MM}_{HH}.sqlite",
    lead_time = seq(0, 72, 1)
  )
  list(T2m = fcst_t2m, PSFC = fcst_psfc)
}

# Print forecast summary
print_forecast_summary <- function(fcst) {
  cat("\nData summary:\n")
  for (param in names(fcst)) {
    cat("- Parameter:", param, "\n")
    for (model in names(fcst[[param]])) {
      cat("  - Forecast model:", model, "\n")
      if (is.data.frame(fcst[[param]][[model]]) && nrow(fcst[[param]][[model]]) > 0) {
        cat("    - Forecast data points:", nrow(fcst[[param]][[model]]), "\n")
      } else {
        cat("    - Forecast data: No valid data found\n")
      }
    }
  }
}

# Observation reading
read_observations <- function(fcst, obs_dir) {
  cat("Step 2: Reading observations...\n")
  obs_t2m <- read_point_obs(
    dttm = unique_valid_dttm(fcst$T2m),
    parameter = "T2m", 
    stations = unique_stations(fcst$T2m),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_pressure <- read_point_obs(
    dttm = unique_valid_dttm(fcst$PSFC),
    parameter = "Ps", 
    stations = unique_stations(fcst$PSFC),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  cat("- Observation T2m data points:", if(is.null(obs_t2m)) 0 else nrow(obs_t2m), "\n")
  cat("- Observation Pressure data points:", if(is.null(obs_pressure)) 0 else nrow(obs_pressure), "\n")
  list(T2m = obs_t2m, Pressure = obs_pressure)
}

# Verification workflow
verify_and_save <- function(fcst, obs, output_dir) {
  cat("Step 3: Processing and verifying...\n")
  # Temperature
  fcst_t2m <- fcst$T2m |>
    scale_param(-273.15, "degC") |>
    common_cases() |>
    join_to_fcst(obs$T2m)
  valid_t2m <- any(sapply(fcst_t2m, function(x) is.data.frame(x) && nrow(x) > 0))
  if (valid_t2m) {
    verif_t2m <- det_verify(fcst_t2m, T2m)
    save_point_verif(verif_t2m, verif_path = file.path(output_dir))
    cat("- Temperature verification saved.\n")
  } else {
    cat("No valid forecast-observation pairs for temperature.\n")
  }
  # Pressure
  fcst_psfc <- fcst$PSFC |>
    scale_param(0.01, "hPa") |>
    common_cases() |>
    join_to_fcst(obs$Pressure)
  valid_psfc <- any(sapply(fcst_psfc, function(x) is.data.frame(x) && nrow(x) > 0))
  if (valid_psfc) {
    verif_psfc <- det_verify(fcst_psfc, Ps)
    save_point_verif(verif_psfc, verif_path = file.path(output_dir))
    cat("- Pressure verification saved.\n")
  } else {
    cat("No valid forecast-observation pairs for pressure.\n")
  }
  if (!valid_t2m && !valid_psfc) {
    cat("No valid forecast-observation pairs found after joining. Exiting.\n")
    quit(status = 1)
  }
}

# Main script
opt <- parse_and_validate_args()
cat("Starting temperature and pressure verification for:", opt$start_date, "to", opt$end_date, "- Domains: d01 & d02\n")
fcst_models <- c("wrf_d01", "wrf_d02")
fcst_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
obs_dir  <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"

fcst <- read_forecasts(opt$start_date, opt$end_date, fcst_models, fcst_dir)
print_forecast_summary(fcst)
obs <- read_observations(fcst, obs_dir)
verify_and_save(fcst, obs, opt$output_dir)
