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

# Parse command line arguments
option_list <- list(
  make_option(c("-s", "--start_date"), type="character", default=NULL, 
              help="Start date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
  make_option(c("-e", "--end_date"), type="character", default=NULL, 
              help="End date in format YYYYMMDDHH", metavar="YYYYMMDDHH"),
  make_option(c("-d", "--domain"), type="character", default="d01", 
              help="WRF domain (d01 or d02) [default= %default]"),
  make_option(c("-o", "--output_dir"), type="character", default="/wrf/WRF_Model/Verification/Results", 
              help="Output directory for verification results [default= %default]")
)

opt <- parse_args(OptionParser(option_list=option_list))

# Validate arguments
stopifnot(!is.null(opt$start_date), !is.null(opt$end_date), 
          nchar(opt$start_date) == 10, nchar(opt$end_date) == 10,
          opt$domain %in% c("d01", "d02"))

cat("Starting temperature verification for:", opt$start_date, "to", opt$end_date, "- Domain:", opt$domain, "\n")

# Define paths and configuration
fcst_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
obs_dir  <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"
fcst_model <- paste0("wrf_", opt$domain)
year <- substr(opt$start_date, 1, 4)
month <- substr(opt$start_date, 5, 6)

# Create output directories
verif_dir <- file.path(opt$output_dir, fcst_model)
dir.create(verif_dir, recursive = TRUE, showWarnings = FALSE)

# Harp verification workflow
cat("Step 1: Reading forecasts...\n")
fcst <- read_point_forecast(
  dttm = seq_dttm(opt$start_date, opt$end_date, "6h"),
  fcst_model = fcst_model,
  parameter = "T2m",
  file_path = file.path(fcst_dir, fcst_model, year, month),
  file_template = "FCTABLE_T2_{YYYY}{MM}_{HH}.sqlite",
  lead_time = seq(0, 48, 1)
)


cat("Step 2: Reading observations...\n")
obs <- read_point_obs(
  dttm = unique_valid_dttm(fcst),
  parameter = "T2m", 
  stations = unique_stations(fcst),
  obs_path = obs_dir,
  obsfile_template = "obstable_{YYYY}{MM}.sqlite"
)

# Print data summary
cat("\nData summary:\n")
if (is.data.frame(fcst) && nrow(fcst) > 0) {
  cat("- Forecast data points:", nrow(fcst), "\n")
} else if (is.list(fcst) && length(fcst) > 0) {
  total_fcst_points <- sum(sapply(fcst, function(x) if(is.data.frame(x)) nrow(x) else 0))
  cat("- Forecast data points:", total_fcst_points, "\n")
} else {
  cat("- Forecast data: No valid data found\n")
}
cat("- Observation data points:", if(is.null(obs)) 0 else nrow(obs), "\n")
cat("- Forecast models:", if(is.data.frame(fcst)) unique(fcst$fcst_model) else if(is.list(fcst)) names(fcst) else "None", "\n")
cat("- Stations:", length(unique_stations(fcst)), "\n")

cat("Step 3: Processing and verifying...\n")
verif <- fcst |>
  scale_param(-273.15, "degC") |>
  common_cases() |>
  join_to_fcst(obs) |>
  det_verify(T2m)

cat("Step 4: Saving results and creating plots...\n")
save_point_verif(verif, verif_path = verif_dir)

