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

# Moisture conversion functions
# Constants
Rd <- 287.05  # Gas constant for dry air (J/kg/K)
Rv <- 461.5   # Gas constant for water vapor (J/kg/K)
epsilon <- Rd / Rv  # ~0.622

# Calculate saturation vapor pressure (Bolton 1980)
calc_es <- function(t) {
  611.2 * exp(17.67 * (t - 273.15) / (t - 29.65))
}

# Convert specific humidity to relative humidity
calc_rh_from_q <- function(q, t, p) {
  es <- calc_es(t)
  e <- (q * p) / (epsilon + q * (1 - epsilon))
  rh <- 100 * e / es
  rh[rh < 0] <- 0
  rh[rh > 100] <- 100
  return(rh)
}

# Convert specific humidity to dew point temperature
calc_td_from_q <- function(q, t, p) {
  e <- (q * p) / (epsilon + q * (1 - epsilon))
  e[e <= 0] <- NA
  td <- 243.5 * log(e / 611.2) / (17.67 - log(e / 611.2)) + 273.15
  return(td)
}

# Convert dew point to relative humidity
calc_rh_from_td <- function(td, t) {
  e <- calc_es(td)
  es <- calc_es(t)
  rh <- 100 * e / es
  rh[rh < 0] <- 0
  rh[rh > 100] <- 100
  return(rh)
}

# Convert dew point to specific humidity
calc_q_from_td <- function(td, p) {
  e <- calc_es(td)
  q <- epsilon * e / (p - (1 - epsilon) * e)
  return(q)
}

# Convert relative humidity to dew point
calc_td_from_rh <- function(rh, t) {
  es <- calc_es(t)
  e <- (rh / 100) * es
  td <- 243.5 * log(e / 611.2) / (17.67 - log(e / 611.2)) + 273.15
  return(td)
}

# Convert relative humidity to specific humidity
calc_q_from_rh <- function(rh, t, p) {
  es <- calc_es(t)
  e <- (rh / 100) * es
  q <- epsilon * e / (p - (1 - epsilon) * e)
  return(q)
}

# Forecast reading
read_forecasts <- function(start_date, end_date, wrf_models, gfs_model, fcst_dir) {
  cat("Step 1: Reading forecasts for both domains...\n")
  leadtime_max <- as.numeric(Sys.getenv("LEADTIME"))

  # Helper function to read forecasts for a model
  read_model_forecasts <- function(models, lead_times, interval_desc) {
    cat("- Reading", interval_desc, "forecasts...\n")
    params <- c("t2m", "psfc", "q2m", "ws10m")
    lapply(setNames(params, params), function(param) {
      read_point_forecast(
        dttm = seq_dttm(start_date, end_date, "6h"),
        fcst_model = models,
        parameter = param,
        file_path = fcst_dir,
        file_template = paste0("{fcst_model}/{YYYY}/{MM}/FCTABLE_", param, "_{YYYY}{MM}_{HH}.sqlite"),
        lead_time = lead_times
      )
    })
  }

  # Read WRF (hourly) and GFS (3-hourly) forecasts
  wrf_fcst <- read_model_forecasts(wrf_models, seq(0, leadtime_max, 1), "WRF (hourly)")
  gfs_fcst <- read_model_forecasts(gfs_model, seq(0, leadtime_max, 3), "GFS (3-hourly)")

  # Combine models for each parameter (WRF + GFS)
  combine_models <- function(wrf_data, gfs_data) {
    as_harp_list(c(as.list(wrf_data), as.list(as_harp_list(list(gfs = gfs_data)))))
  }

  # Create WRF-only harp lists
  wrf_only_models <- function(wrf_data) {
    as_harp_list(as.list(wrf_data))
  }

  combined <- list(
    t2m = combine_models(wrf_fcst$t2m, gfs_fcst$t2m),
    psfc = combine_models(wrf_fcst$psfc, gfs_fcst$psfc),
    q2m = combine_models(wrf_fcst$q2m, gfs_fcst$q2m),
    ws = combine_models(wrf_fcst$ws10m, gfs_fcst$ws10m),
    pcp = combine_models(wrf_fcst$pcp, gfs_fcst$pcp)
  )

  wrf_only <- list(
    t2m = wrf_only_models(wrf_fcst$t2m),
    psfc = wrf_only_models(wrf_fcst$psfc),
    q2m = wrf_only_models(wrf_fcst$q2m),
    ws = wrf_only_models(wrf_fcst$ws10m),
    pcp = wrf_only_models(wrf_fcst$pcp)
  )

  list(combined = combined, wrf_only = wrf_only)
}

# Print forecast summary
print_forecast_summary <- function(fcst, title = "") {
  if (title != "") cat("\n", title, "\n")
  cat("Data summary:\n")
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
  
  # Helper function to read obs with error handling
  read_obs_safe <- function(param, desc = NULL) {
    tryCatch({
      obs <- read_point_obs(
        dttm = sort(unique(unlist(lapply(fcst, unique_valid_dttm)))),
        parameter = param,
        stations = unique_stations(fcst$q2m),
        obs_path = obs_dir,
        obsfile_template = "obstable_{YYYY}{MM}.sqlite"
      )
      if (!is.null(obs) && nrow(obs) > 0) {
        if (!is.null(desc)) cat("  - Found", desc, "observations\n")
        return(obs)
      }
      NULL
    }, error = function(e) NULL)
  }
  
  # Read standard observations
  obs_t2m <- read_point_obs(
    dttm = sort(unique(unlist(lapply(fcst, unique_valid_dttm)))),
    parameter = "T2m",
    stations = unique_stations(fcst$t2m),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_pressure <- read_point_obs(
    dttm = sort(unique(unlist(lapply(fcst, unique_valid_dttm)))),
    parameter = "Ps",
    stations = unique_stations(fcst$psfc),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_ws <- read_point_obs(
    dttm = sort(unique(unlist(lapply(fcst, unique_valid_dttm)))),
    parameter = "S10m",
    stations = unique_stations(fcst$ws),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  obs_pcp <- read_point_obs(
    dttm = sort(unique(unlist(lapply(fcst, unique_valid_dttm)))),
    parameter = "Pcp",
    stations = unique_stations(fcst$pcp),
    obs_path = obs_dir,
    obsfile_template = "obstable_{YYYY}{MM}.sqlite"
  )
  
  # Try moisture parameters
  cat("- Checking available moisture parameters...\n")
  obs_td <- read_obs_safe("Td2m", "Td2m (dew point)")
  obs_rh <- read_obs_safe("RH2m", "RH2m (relative humidity)")
  obs_q <- read_obs_safe("Q2m", "Q2m (specific humidity)")
  
  if (is.null(obs_td) && is.null(obs_rh) && is.null(obs_q)) {
    cat("  - No moisture observations found (Td2m, RH2m, or Q2m)\n")
  }
  
  cat("- Observation T2m data points:", if(is.null(obs_t2m)) 0 else nrow(obs_t2m), "\n")
  cat("- Observation Pressure data points:", if(is.null(obs_pressure)) 0 else nrow(obs_pressure), "\n")
  cat("- Observation Wind Speed data points:", if(is.null(obs_ws)) 0 else nrow(obs_ws), "\n")
  cat("- Observation Precipitation data points:", if(is.null(obs_pcp)) 0 else nrow(obs_pcp), "\n")
  
  list(T2m = obs_t2m, Pressure = obs_pressure, Td2m = obs_td, RH2m = obs_rh, Q2m = obs_q, WindSpeed = obs_ws, Pcp = obs_pcp)
}

# Verification workflow
verify_and_save <- function(fcst, obs, output_dir) {
  cat("Step 3: Processing and verifying...\n")
  
  # Helper function to verify and save single parameter
  verify_param <- function(data, obs_data, obs_param, param_name) {
    if (any(sapply(data, function(x) is.data.frame(x) && nrow(x) > 0))) {
      verif <- det_verify(data, !!sym(obs_param))
      save_point_verif(verif, verif_path = file.path(output_dir))
      cat("-", param_name, "verification saved.\n")
      return(TRUE)
    }
    cat("No valid forecast-observation pairs for", tolower(param_name), ".\n")
    return(FALSE)
  }
  
  # Temperature
  valid_t2m <- verify_param(
    fcst$t2m |> scale_param(-273.15, "degC") |> common_cases() |> join_to_fcst(obs$T2m),
    obs$T2m, "T2m", "Temperature"
  )
  
  # Pressure
  valid_psfc <- verify_param(
    scale_param(fcst$psfc, 0.01, "hPa", mult = TRUE) |> common_cases() |> join_to_fcst(obs$Pressure),
    obs$Pressure, "Ps", "Pressure"
  )
  
  # Moisture verification
  valid_moisture <- verify_moisture(fcst, obs, output_dir)
  
  # Wind Speed
  valid_ws <- verify_param(
    fcst$ws |> set_units("m/s") |> common_cases() |> join_to_fcst(obs$WindSpeed),
    obs$WindSpeed, "S10m", "Wind Speed"
  )

  # Precipitation (accumulated, mm)
  valid_pcp <- verify_param(
    fcst$pcp |> set_units("mm") |> common_cases() |> join_to_fcst(obs$Pcp),
    obs$Pcp, "Pcp", "Precipitation"
  )
  
  if (!valid_t2m && !valid_psfc && !valid_moisture && !valid_ws) {
    cat("No valid forecast-observation pairs found after joining. Exiting.\n")
    quit(status = 1)
  }
}

# Moisture verification helper
verify_moisture <- function(fcst, obs, output_dir) {
  cat("- Processing moisture parameters...\n")
  
  # Prepare merged moisture data
  fcst_moisture <- lapply(names(fcst$q2m), function(model) {
    q2m_df <- fcst$q2m[[model]]
    t2m_df <- fcst$t2m[[model]]
    psfc_df <- fcst$psfc[[model]]
    
    if (!is.data.frame(q2m_df) || !is.data.frame(t2m_df) || !is.data.frame(psfc_df) ||
        nrow(q2m_df) == 0 || nrow(t2m_df) == 0 || nrow(psfc_df) == 0) return(NULL)
    
    # Find forecast value columns - exclude metadata
    get_fcst_col <- function(df) {
      cols <- names(df)[!(names(df) %in% c("SID", "valid_dttm", "lead_time", "fcst_dttm", "fcst_cycle", "units", "fcst_model", "parameter", "z"))]
      if (length(cols) == 0) return(NULL)
      cols[1]
    }
    
    q2m_col <- get_fcst_col(q2m_df)
    t2m_col <- get_fcst_col(t2m_df)
    psfc_col <- get_fcst_col(psfc_df)
    
    if (is.null(q2m_col) || is.null(t2m_col) || is.null(psfc_col)) {
      cat("  - Warning: Could not find forecast columns for model", model, "\n")
      return(NULL)
    }
    
    # Merge dataframes
    q2m_df |>
      select(SID, valid_dttm, lead_time, fcst_dttm, q2m_val = all_of(q2m_col)) |>
      inner_join(t2m_df |> select(SID, valid_dttm, lead_time, fcst_dttm, t2m_val = all_of(t2m_col)),
                 by = c("SID", "valid_dttm", "lead_time", "fcst_dttm")) |>
      inner_join(psfc_df |> select(SID, valid_dttm, lead_time, fcst_dttm, psfc_val = all_of(psfc_col)),
                 by = c("SID", "valid_dttm", "lead_time", "fcst_dttm"))
  })
  names(fcst_moisture) <- names(fcst$q2m)
  
  if (!any(sapply(fcst_moisture, function(x) !is.null(x) && nrow(x) > 0))) {
    cat("  - No valid forecast moisture data available.\n")
    return(FALSE)
  }
  
  # Complete observations: calculate missing moisture parameters from available ones
  obs_complete <- complete_moisture_obs(obs, fcst_moisture)
  
  # Verify all three moisture parameters
  valid_td <- verify_moisture_param(fcst_moisture, obs_complete$Td2m, "Td2m", "Dew Point Temperature", 
                                     calc_td_from_q, "degC", -273.15, output_dir)
  valid_rh <- verify_moisture_param(fcst_moisture, obs_complete$RH2m, "RH2m", "Relative Humidity",
                                     calc_rh_from_q, "percent", 0, output_dir)
  valid_q <- verify_moisture_param(fcst_moisture, obs_complete$Q2m, "Q2m", "Specific Humidity",
                                    NULL, "kg/kg", 0, output_dir)
  
  if (!valid_td && !valid_rh && !valid_q) {
    cat("  - No valid forecast-observation pairs for any moisture parameter.\n")
    return(FALSE)
  }
  return(TRUE)
}

# Complete moisture observations by calculating missing parameters
complete_moisture_obs <- function(obs, fcst_moisture) {
  cat("- Completing moisture observations...\n")
  
  # Check what's available
  has_td <- !is.null(obs$Td2m) && nrow(obs$Td2m) > 0
  has_rh <- !is.null(obs$RH2m) && nrow(obs$RH2m) > 0
  has_q <- !is.null(obs$Q2m) && nrow(obs$Q2m) > 0
  
  if (!has_td && !has_rh && !has_q) {
    cat("  - No moisture observations available to complete.\n")
    return(list(Td2m = NULL, RH2m = NULL, Q2m = NULL))
  }
  
  # Get t2m and psfc observations for conversions
  obs_t2m <- obs$T2m
  obs_ps <- obs$Pressure
  
  # Start with what we have
  obs_td <- obs$Td2m
  obs_rh_out <- obs$RH2m
  obs_q_out <- obs$Q2m
  
  # Calculate missing parameters based on what's available
  if (has_td) {
    cat("  - Using Td2m observations as base\n")
    
    if (!has_q && !is.null(obs_ps)) {
      cat("    - Calculating Q2m from Td2m\n")
      obs_q_out <- obs_td |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Q2m = calc_q_from_td(Td2m, Ps), units = "kg/kg") |>
        select(valid_dttm, SID, lon, lat, elev, Q2m, units)
    }
    
    if (!has_rh && !is.null(obs_t2m)) {
      cat("    - Calculating RH2m from Td2m\n")
      obs_rh_out <- obs_td |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        mutate(RH2m = calc_rh_from_td(Td2m, T2m), units = "percent") |>
        select(valid_dttm, SID, lon, lat, elev, RH2m, units)
    }
  }
  
  if (has_rh && !is.null(obs_t2m)) {
    cat("  - Using RH2m observations for calculations\n")
    
    if (!has_td) {
      cat("    - Calculating Td2m from RH2m\n")
      obs_td <- obs_rh_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        mutate(Td2m = calc_td_from_rh(RH2m, T2m), units = "degC") |>
        select(valid_dttm, SID, lon, lat, elev, Td2m, units)
    }
    
    if (!has_q && !is.null(obs_ps)) {
      cat("    - Calculating Q2m from RH2m\n")
      obs_q_out <- obs_rh_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Q2m = calc_q_from_rh(RH2m, T2m, Ps), units = "kg/kg") |>
        select(valid_dttm, SID, lon, lat, elev, Q2m, units)
    }
  }
  
  if (has_q && !is.null(obs_t2m) && !is.null(obs_ps)) {
    cat("  - Using Q2m observations for calculations\n")
    
    if (!has_td) {
      cat("    - Calculating Td2m from Q2m\n")
      obs_td <- obs_q_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(Td2m = calc_td_from_q(Q2m, T2m, Ps) - 273.15, units = "degC") |>
        select(valid_dttm, SID, lon, lat, elev, Td2m, units)
    }
    
    if (!has_rh) {
      cat("    - Calculating RH2m from Q2m\n")
      obs_rh_out <- obs_q_out |>
        inner_join(obs_t2m |> select(SID, valid_dttm, T2m), by = c("SID", "valid_dttm")) |>
        inner_join(obs_ps |> select(SID, valid_dttm, Ps), by = c("SID", "valid_dttm")) |>
        mutate(RH2m = calc_rh_from_q(Q2m, T2m, Ps), units = "percent") |>
        select(valid_dttm, SID, lon, lat, elev, RH2m, units)
    }
  }
  
  list(Td2m = obs_td, RH2m = obs_rh_out, Q2m = obs_q_out)
}

# Moisture parameter verification
verify_moisture_param <- function(fcst_moisture, obs_data, param, param_desc, 
                                   calc_func, units, offset, output_dir) {
  if (is.null(obs_data) || nrow(obs_data) == 0) return(FALSE)
  
  cat("  - Verifying", param_desc, paste0("(", param, ")...\n"))
  
  fcst_list <- lapply(fcst_moisture, function(df) {
    if (is.null(df) || nrow(df) == 0) return(NULL)
    
    if (!is.null(calc_func)) {
      # Calculate derived parameter
      q_vals <- as.numeric(df$q2m_val)
      t_vals <- as.numeric(df$t2m_val)
      p_vals <- as.numeric(df$psfc_val)
      
      df$fcst <- calc_func(q_vals, t_vals, p_vals) + offset
    } else {
      # Use q2m directly
      df$fcst <- df$q2m_val
    }
    
    df$parameter <- param
    df$units <- units
    result <- df |> select(SID, valid_dttm, lead_time, fcst_dttm, parameter, fcst, units)
    return(result)
  })
  names(fcst_list) <- names(fcst_moisture)
  
  cat("  - Creating harp_list and joining...\n")
  cat("  - Observation rows:", nrow(obs_data), "\n")
  if (nrow(obs_data) > 0) {
    cat("  - Obs columns:", paste(names(obs_data), collapse=", "), "\n")
    cat("  - Obs valid_dttm range: [", min(obs_data$valid_dttm, na.rm=TRUE), ",", max(obs_data$valid_dttm, na.rm=TRUE), "]\n")
  }
  
  fcst_list <- as_harp_list(fcst_list) |> set_units(units) |> common_cases() |> join_to_fcst(obs_data)

  # Filter out rows with NA in forecast or observation value to avoid plotting/binning errors
  for (model_name in names(fcst_list)) {
    model_data <- fcst_list[[model_name]]
    if (is.data.frame(model_data) && nrow(model_data) > 0) {
      # If the observation column exists (param), remove rows where it's NA; always remove NA fcst
      if (param %in% names(model_data)) {
        model_data <- model_data |> filter(!is.na(fcst) & !is.na(.data[[param]]))
      } else {
        model_data <- model_data |> filter(!is.na(fcst))
      }
      fcst_list[[model_name]] <- model_data
    }
  }

  # Debug: Check joined data after NA filtering
  for (model_name in names(fcst_list)) {
    model_data <- fcst_list[[model_name]]
    if (is.data.frame(model_data)) {
      cat("  - Model", model_name, "after join+filter: rows =", nrow(model_data), "\n")
      if (nrow(model_data) > 0) {
        cat("    - Columns:", paste(names(model_data), collapse=", "), "\n")
      }
    }
  }
  
  # If no model has rows after filtering, skip verification
  if (!any(sapply(fcst_list, function(x) is.data.frame(x) && nrow(x) > 0))) {
    cat("  - No valid pairs found after join+filter\n")
    return(FALSE)
  }

  # Run det_verify
  verif <- tryCatch({
    det_verify(fcst_list, !!sym(param))
  }, error = function(e) {
    cat("  - det_verify error for", param, ":", e$message, "\n")
    return(NULL)
  })

  if (is.null(verif)) {
    cat("  -", param_desc, "verification skipped due to det_verify error.\n")
    return(FALSE)
  }

  save_point_verif(verif, verif_path = file.path(output_dir))
  cat("  -", param_desc, "verification saved.\n")
  return(TRUE)
}

# Main script
opt <- parse_and_validate_args()
cat("Starting verification for:", opt$start_date, "to", opt$end_date, "- Models: WRF (d01 & d02) and GFS\n")
cat("Parameters: Temperature, Pressure, Moisture (Td/RH/Q), Wind Speed\n")
cat("Note: WRF models use hourly intervals, GFS uses 3-hourly intervals\n")
cat("Note: Moisture verification uses available obs (Td2m, RH2m, or Q2m)\n")
wrf_models <- c("wrf_d01", "wrf_d02")
gfs_model <- "gfs"
fcst_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
obs_dir  <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"

fcst_sets <- read_forecasts(opt$start_date, opt$end_date, wrf_models, gfs_model, fcst_dir)
print_forecast_summary(fcst_sets$combined, "Combined forecasts (WRF + GFS):")
print_forecast_summary(fcst_sets$wrf_only, "WRF-only forecasts (d01 & d02):")
obs <- read_observations(fcst_sets$combined, obs_dir)

cat("\n=== Forecast/observation time alignment check ===\n")

for (m in names(fcst_sets$combined$t2m)) {
  cat("Model:", m, "\n")
  tmp <- fcst_sets$combined$t2m[[m]]
  if (!is.null(tmp) && nrow(tmp) > 0) {
    print(range(tmp$valid_dttm))
    cat("Unique lead times:", paste(sort(unique(tmp$lead_time)), collapse = ", "), "\n")
  }
}

cat("\nObservation valid_dttm range:\n")
if (!is.null(obs$T2m) && nrow(obs$T2m) > 0) {
  print(range(obs$T2m$valid_dttm))
  cat("Observation time step (hours):",
      median(diff(sort(unique(obs$T2m$valid_dttm))) / 3600), "\n")
} else {
  cat("No T2m observations available to compute time range or step.\n")
}
# Run verification for combined set (WRF + GFS)
verify_and_save(fcst_sets$combined, obs, opt$output_dir)

# Run verification for WRF-only set
verify_and_save(fcst_sets$wrf_only, obs, opt$output_dir)
