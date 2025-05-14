####################################################
## Comprehensive verification for multiple parameters
####################################################

args = commandArgs(trailingOnly=TRUE)
if (length(args) < 2 || length(args) > 3){
  stop("Usage: Rscript verify_parameters.R <start_time> <end_time> [period_name]
  Arguments:
  - start_time: Start time in yyyymmddHH format
  - end_time: End time in yyyymmddHH format
  - period_name: Optional name for the verification period (e.g., 'weekly', 'monthly', '10day'). 
                 Default is 'custom'")
}

start_time = args[1]
end_time = args[2]
period_name = "custom"

if (length(args) == 3) {
  period_name = args[3]
}

if (nchar(start_time) != 10 || nchar(end_time) != 10){
  stop("Times must be in yyyymmddHH format")
}

library(harp)
library(dplyr)
library(ggplot2)

# Path settings
sqlite_fc_path <- "/home/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
sqlite_obs_path <- "/home/wrf/WRF_Model/Verification/SQlite_tables/Obs"
base_figure_dir <- "/home/wrf/WRF_Model/Verification/Data/Figures"
base_results_dir <- "/home/wrf/WRF_Model/Verification/Data/Results"

# Create specific directories for this verification period
figure_dir <- file.path(base_figure_dir, period_name)
results_dir <- file.path(base_results_dir, period_name)

# Create directories if they don't exist
if (!dir.exists(figure_dir)) dir.create(figure_dir, recursive = TRUE)
if (!dir.exists(results_dir)) dir.create(results_dir, recursive = TRUE)

# Calculate the number of days in this verification period
start_date <- as.POSIXct(start_time, format="%Y%m%d%H", tz="UTC")
end_date <- as.POSIXct(end_time, format="%Y%m%d%H", tz="UTC")
days_diff <- as.numeric(difftime(end_date, start_date, units="days"))
cat(sprintf("Performing verification for a %g day period (%s)\n", round(days_diff, 1), period_name))

# Define models to verify
models <- c("wrf_d01", "wrf_d02")

# Define parameters to verify - add Pressure and Q2 (specific humidity)
parameters <- c("T2m", "WS10m", "Pcp", "Pressure", "Q2")

# Function to verify a single parameter
verify_parameter <- function(parameter, model, date_range, sqlite_fc_path, sqlite_obs_path, figure_dir, results_dir, period_name) {
  cat("Verifying", parameter, "for model", model, "for", period_name, "period\n")
  
  # Read forecast data
  point_data <- read_point_forecast(
    dttm = date_range,
    fcst_model = model,
    fcst_type = "det", 
    parameter = parameter,
    lead_time = seq(0, 72, 1),
    file_path = sqlite_fc_path,
    file_template = "fctable_det"
  )
  
  # If data is empty, return
  if (is.null(point_data) || nrow(point_data) == 0) {
    cat("No forecast data found for", parameter, "in model", model, "\n")
    return(NULL)
  }
  
  # Read observation data
  obs_data <- read_point_obs(
    dttm = unique_valid_dttm(point_data),
    parameter = parameter,
    stations = pull_stations(point_data), 
    obs_path = sqlite_obs_path
  )
  
  # If no observation data, return
  if (is.null(obs_data) || nrow(obs_data) == 0) {
    cat("No observation data found for", parameter, "\n")
    return(NULL)
  }
  
  # Apply unit conversions if necessary
  if (parameter == "T2m") {
    # Convert temperature to Celsius if needed
    point_data <- mutate(scale_param(point_data, -273.15, "degC"))
  } else if (parameter == "Pressure") {
    # Convert pressure to hPa if it's in Pa
    if (mean(pull(point_data, fcst), na.rm = TRUE) > 10000) {
      point_data <- mutate(scale_param(point_data, 0.01, "hPa"))
    }
  } else if (parameter == "Q2") {
    # Convert specific humidity to g/kg for better scale in plots
    point_data <- mutate(scale_param(point_data, 1000, "g/kg"))
  }
  
  # Join forecasts and observations
  point_data <- join_to_fcst(point_data, obs_data)
  
  # Set thresholds based on parameter
  thresholds <- NULL
  if (parameter == "T2m") {
    thresholds <- seq(-10, 30, 5)
  } else if (parameter == "WS10m") {
    thresholds <- c(2, 5, 10, 15, 20)
  } else if (parameter == "Pcp") {
    thresholds <- c(0.1, 1, 5, 10, 20)
  } else if (parameter == "Pressure") {
    thresholds <- seq(850, 1050, 25)
  } else if (parameter == "Q2") {
    thresholds <- c(1, 3, 5, 10, 15)  # g/kg thresholds
  }
  
  # Verify
  if (!is.null(thresholds)) {
    verif_scores <- det_verify(point_data, parameter = !!sym(parameter), thresholds = thresholds)
  } else {
    verif_scores <- det_verify(point_data, parameter = !!sym(parameter))
  }
  
  # Save verification results
  model_results_dir <- file.path(results_dir, model)
  if (!dir.exists(model_results_dir)) dir.create(model_results_dir, recursive = TRUE)
  save_point_verif(verif_scores, model_results_dir)
  
  # Create and save standard plots
  plots <- c("mae", "rmse", "bias", "hexbin")
  for (plot_type in plots) {
    png_file <- file.path(figure_dir, paste0(model, "_", parameter, "_", plot_type, "_", period_name, ".png"))
    png(filename = png_file, width = 1000, height = 600, res = 100)
    print(plot_point_verif(verif_data = verif_scores, score = sym(plot_type)))
    dev.off()
    cat("Created", png_file, "\n")
  }
  
  # Create threshold-based plots if applicable
  if (!is.null(thresholds)) {
    # Hit rate by threshold
    png_file <- file.path(figure_dir, paste0(model, "_", parameter, "_hit_rate_", period_name, ".png"))
    png(filename = png_file, width = 1000, height = 600, res = 100)
    print(plot_point_verif(verif_data = verif_scores, score = hit_rate, facet_by = vars(threshold)))
    dev.off()
    
    # Frequency bias by threshold
    png_file <- file.path(figure_dir, paste0(model, "_", parameter, "_freq_bias_", period_name, ".png"))
    png(filename = png_file, width = 1000, height = 600, res = 100)
    print(plot_point_verif(verif_data = verif_scores, score = frequency_bias, x_axis = threshold, 
                     facet_by = vars(lead_time), filter_by = vars(lead_time %in% seq(24, 72, 24))))
    dev.off()
  }
  
  return(verif_scores)
}

# Run verification
date_range <- seq_dttm(start_time, end_time, by = "1h")
for (model in models) {
  for (param in parameters) {
    verify_parameter(param, model, date_range, sqlite_fc_path, sqlite_obs_path, 
                    figure_dir, results_dir, period_name)
  }
}
