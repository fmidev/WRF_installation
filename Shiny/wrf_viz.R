library(shiny)
library(ncdf4)
library(plotly)
library(viridis)
library(lubridate)

ui <- fluidPage(
  theme = bslib::bs_theme(bootswatch = "flatly"),
  titlePanel("WRF Output Visualizer"),
  
  sidebarLayout(
    sidebarPanel(
      width = 3,
      h4("Forecast Selection"),
      textInput("base_dir", "WRF Output Directory:", value = "/wrf/WRF_Model/out"),
      actionButton("refresh_files", "Scan Directory", class = "btn-primary"),
      br(), br(),
      uiOutput("date_selector"),
      uiOutput("hour_selector"),
      uiOutput("domain_selector"),
      br(),
      actionButton("load_forecast", "Load Forecast", class = "btn-success btn-lg", style = "width: 100%;"),
      hr(),
      
      h4("Variable Selection"),
      uiOutput("variable_selector"),
      hr(),
      
      h4("Display Options"),
      selectInput("color_palette", "Color Palette:",
                  choices = c("viridis", "plasma", "magma", "inferno", "cividis", "turbo", "RdBu", "RdYlBu"),
                  selected = "viridis"),
      checkboxInput("reverse_colors", "Reverse Colors", FALSE),
      numericInput("plot_height", "Plot Height (px):", value = 600, min = 400, max = 1200, step = 50),
      hr(),
      uiOutput("time_slider")
    ),
    
    mainPanel(
      width = 9,
      tabsetPanel(
        id = "main_tabs",
        tabPanel("Animated Field",
                 br(), uiOutput("plot_ui"), br(),
                 fluidRow(
                   column(6, h5("Forecast Information:"), verbatimTextOutput("forecast_info")),
                   column(6, h5("Variable Statistics:"), verbatimTextOutput("var_stats"))
                 )),
        
        tabPanel("Point Time Series",
                 br(),
                 fluidRow(
                   column(4, numericInput("point_lat", "Latitude:", value = 45.0)),
                   column(4, numericInput("point_lon", "Longitude:", value = 50.0)),
                   column(4, br(), actionButton("extract_point", "Extract Time Series", class = "btn-success"))
                 ),
                 br(), plotlyOutput("timeseries_plot", height = "500px"))
      )
    )
  )
)

server <- function(input, output, session) {
  
  rv <- reactiveValues(
    available_files = NULL, available_dates = NULL, available_hours = NULL,
    available_domains = NULL, loaded_files = NULL, times = NULL,
    lats = NULL, lons = NULL, first_nc = NULL, point_data = NULL
  )
  
  scan_nc_files <- function(base_dir) {
    if (!dir.exists(base_dir)) return(NULL)
    
    # Look for subdirectories matching YYYYMMDDHH pattern
    subdirs <- list.dirs(base_dir, full.names = TRUE, recursive = FALSE)
    if (length(subdirs) == 0) return(NULL)
    
    # Filter for YYYYMMDDHH pattern (10 digits)
    subdirs <- subdirs[grepl("/[0-9]{10}$", subdirs)]
    if (length(subdirs) == 0) return(NULL)
    
    all_files <- list()
    
    for (subdir in subdirs) {
      # Extract YYYYMMDDHH from directory name
      dir_name <- basename(subdir)
      date_str <- paste0(substr(dir_name, 1, 4), "-", substr(dir_name, 5, 6), "-", substr(dir_name, 7, 8))
      hour_str <- as.integer(substr(dir_name, 9, 10))
      
      # Find WRF output files in this directory
      files <- list.files(subdir, pattern = "^wrfout_d[0-9]+_[0-9]{4}-[0-9]{2}-[0-9]{2}_[0-9]{2}:[0-9]{2}:[0-9]{2}$", 
                          full.names = TRUE, recursive = FALSE)
      
      if (length(files) > 0) {
        file_info <- do.call(rbind, lapply(files, function(f) {
          parts <- strsplit(basename(f), "_")[[1]]
          data.frame(
            path = f, domain = parts[2], date = date_str,
            hour = hour_str,
            datetime = paste(date_str, sprintf("%02d:00:00", hour_str)),
            stringsAsFactors = FALSE
          )
        }))
        all_files[[subdir]] <- file_info
      }
    }
    
    if (length(all_files) == 0) return(NULL)
    
    return(do.call(rbind, all_files))
  }
  
  observeEvent(input$refresh_files, {
    rv$available_files <- scan_nc_files(input$base_dir)
    
    if (is.null(rv$available_files)) {
      showNotification("No WRF output files found in the specified directory.", type = "warning")
    } else {
      rv$available_dates <- unique(rv$available_files$date)
      rv$available_hours <- sort(unique(rv$available_files$hour))
      rv$available_domains <- unique(rv$available_files$domain)
      showNotification(paste("Found", nrow(rv$available_files), "WRF output files."), type = "message")
    }
  })
  
  observe({
    rv$available_files <- scan_nc_files(input$base_dir)
    if (!is.null(rv$available_files)) {
      rv$available_dates <- unique(rv$available_files$date)
      rv$available_hours <- sort(unique(rv$available_files$hour))
      rv$available_domains <- unique(rv$available_files$domain)
    }
  })
  
  output$date_selector <- renderUI({
    req(rv$available_dates)
    selectInput("forecast_date", "Forecast Date:",
                choices = sort(rv$available_dates, decreasing = TRUE),
                selected = rv$available_dates[1])
  })
  
  output$hour_selector <- renderUI({
    req(rv$available_hours)
    selectInput("forecast_hour", "Initial Hour:",
                choices = setNames(rv$available_hours, sprintf("%02d:00", rv$available_hours)),
                selected = rv$available_hours[1])
  })
  
  output$domain_selector <- renderUI({
    req(rv$available_domains)
    selectInput("forecast_domain", "Domain:", choices = rv$available_domains, selected = rv$available_domains[1])
  })
  
  observeEvent(input$load_forecast, {
    req(input$forecast_date, input$forecast_hour, input$forecast_domain)
    
    forecast_files <- rv$available_files[
      rv$available_files$date == input$forecast_date &
      rv$available_files$hour == as.integer(input$forecast_hour) &
      rv$available_files$domain == input$forecast_domain, ]
    forecast_files <- forecast_files[order(forecast_files$hour), ]
    
    if (nrow(forecast_files) == 0) {
      showNotification("No files found for selected forecast.", type = "error")
      return()
    }
    
    withProgress(message = 'Loading forecast...', value = 0, {
      tryCatch({
        all_times <- c()
        if (!is.null(rv$first_nc)) {
          nc_close(rv$first_nc)
          rv$first_nc <- NULL
        }
        
        for (i in 1:nrow(forecast_files)) {
          incProgress(1/nrow(forecast_files), detail = paste("File", i, "of", nrow(forecast_files)))
          nc <- nc_open(forecast_files$path[i])
          
          times_var <- ncvar_get(nc, "Times")
          file_time <- if (is.matrix(times_var)) {
            apply(times_var, 2, function(x) paste(x, collapse = ""))
          } else as.character(times_var)
          file_time <- ymd_hms(file_time, tz = "UTC")
          all_times <- if (i == 1) file_time else c(all_times, file_time)
          
          if (i == 1) {
            xlat_data <- ncvar_get(nc, "XLAT")
            xlong_data <- ncvar_get(nc, "XLONG")
            rv$lats <- if (length(dim(xlat_data)) == 3) xlat_data[1,,] else xlat_data
            rv$lons <- if (length(dim(xlong_data)) == 3) xlong_data[1,,] else xlong_data
            rv$first_nc <- nc
          } else nc_close(nc)
        }
        
        rv$times <- all_times
        rv$loaded_files <- forecast_files
        showNotification(
          paste("Loaded", nrow(forecast_files), "forecast hours from", 
                strftime(min(all_times), "%H:%M", tz = "UTC"), "to", strftime(max(all_times), "%H:%M", tz = "UTC")), 
          type = "message", duration = 5)
      }, error = function(e) {
        showNotification(paste("Error loading forecast:", e$message), type = "error")
      })
    })
  })
  
  output$variable_selector <- renderUI({
    req(rv$first_nc)
    all_var_names <- names(rv$first_nc$var)
    
    # Only 2D surface variables (no vertical levels)
    common_vars <- c(
      "T2" = "2m Temperature", "Q2" = "2m Mixing Ratio",
      "PSFC" = "Surface Pressure", "SNOWH" = "Snow Depth",
      "SST" = "Sea Surface Temperature",
      "Wind_Speed_10m" = "10m Wind Speed & Direction (derived)", 
      "Total_Precip" = "Total Precipitation (derived)"
    )
    
    # Check which variables are available (include derived variables)
    available_common <- common_vars[names(common_vars) %in% all_var_names | 
                                     grepl("Wind_", names(common_vars)) | 
                                     names(common_vars) == "Total_Precip"]
    
    has_wind_10m <- all(c("U10", "V10") %in% all_var_names)
    has_precip <- all(c("RAINC", "RAINNC") %in% all_var_names)
    
    if (!has_wind_10m) available_common <- available_common[!names(available_common) == "Wind_Speed_10m"]
    if (!has_precip) available_common <- available_common[!names(available_common) == "Total_Precip"]
    
    selectInput("variable", "Select Variable:",
                choices = setNames(names(available_common), available_common),
                selected = if("T2" %in% names(available_common)) "T2" else names(available_common)[1])
  })
  

  
  output$time_slider <- renderUI({
    req(rv$times)
    if (length(rv$times) > 1) {
      sliderInput("time_step", "Time Step:",
                  min = 1, max = length(rv$times), value = 1, step = 1,
                  animate = animationOptions(interval = 500, loop = TRUE))
    }
  })
  
  get_variable_data <- reactive({
    req(rv$loaded_files, input$variable, rv$first_nc)
    
    if (input$variable == "Wind_Speed_10m") return(get_wind_derived("U10", "V10", "speed"))
    if (input$variable == "Total_Precip") return(get_total_precip())
    
    withProgress(message = 'Loading variable data...', value = 0, {
      all_data <- list()
      
      for (i in 1:nrow(rv$loaded_files)) {
        incProgress(1/nrow(rv$loaded_files))
        nc <- nc_open(rv$loaded_files$path[i])
        
        data <- ncvar_get(nc, input$variable)
        if (length(dim(data)) == 3) data <- data[1,,]
        
        all_data[[i]] <- data
        if (i != 1) nc_close(nc)
      }
      
      if (length(all_data) > 1) {
        combined <- array(0, dim = c(length(all_data), nrow(all_data[[1]]), ncol(all_data[[1]])))
        for (i in 1:length(all_data)) combined[i,,] <- all_data[[i]]
        return(combined)
      } else return(all_data[[1]])
    })
  })
  
  get_total_precip <- function() {
    req(rv$loaded_files, rv$first_nc)
    
    withProgress(message = 'Computing total precipitation...', value = 0, {
      all_data <- list()
      
      for (i in 1:nrow(rv$loaded_files)) {
        incProgress(1/nrow(rv$loaded_files))
        nc <- nc_open(rv$loaded_files$path[i])
        
        rainc <- ncvar_get(nc, "RAINC")
        rainnc <- ncvar_get(nc, "RAINNC")
        if (length(dim(rainc)) == 3) {
          rainc <- rainc[1,,]
          rainnc <- rainnc[1,,]
        }
        
        all_data[[i]] <- rainc + rainnc
        if (i != 1) nc_close(nc)
      }
      
      if (length(all_data) > 1) {
        combined <- array(0, dim = c(length(all_data), nrow(all_data[[1]]), ncol(all_data[[1]])))
        for (i in 1:length(all_data)) combined[i,,] <- all_data[[i]]
        return(combined)
      } else return(all_data[[1]])
    })
  }
  
  get_wind_derived <- function(u_var, v_var, type) {
    req(rv$loaded_files, rv$first_nc)
    
    withProgress(message = paste('Computing', type, '...'), value = 0, {
      all_data <- list()
      
      for (i in 1:nrow(rv$loaded_files)) {
        incProgress(1/nrow(rv$loaded_files))
        nc <- nc_open(rv$loaded_files$path[i])
        
        u_data <- ncvar_get(nc, u_var)
        if (length(dim(u_data)) == 3) u_data <- u_data[1,,]
        v_data <- ncvar_get(nc, v_var)
        if (length(dim(v_data)) == 3) v_data <- v_data[1,,]
        
        data <- if (type == "speed") {
          sqrt(u_data^2 + v_data^2)
        } else {
          (atan2(u_data, v_data) * 180 / pi + 180) %% 360
        }
        
        all_data[[i]] <- data
        if (i != 1) nc_close(nc)
      }
      
      if (length(all_data) > 1) {
        combined <- array(0, dim = c(length(all_data), nrow(all_data[[1]]), ncol(all_data[[1]])))
        for (i in 1:length(all_data)) combined[i,,] <- all_data[[i]]
        return(combined)
      } else return(all_data[[1]])
    })
  }
  
  get_wind_component <- function(var_name) {
    req(rv$loaded_files, rv$first_nc)
    
    all_data <- list()
    
    for (i in 1:nrow(rv$loaded_files)) {
      nc <- nc_open(rv$loaded_files$path[i])
      
      data <- ncvar_get(nc, var_name)
      if (length(dim(data)) == 3) data <- data[1,,]
      
      all_data[[i]] <- data
      if (i != 1) nc_close(nc)
    }
    
    if (length(all_data) > 1) {
      combined <- array(0, dim = c(length(all_data), nrow(all_data[[1]]), ncol(all_data[[1]])))
      for (i in 1:length(all_data)) combined[i,,] <- all_data[[i]]
      return(combined)
    } else return(all_data[[1]])
  }
  
  # Store all data for fast updates
  all_plot_data <- reactiveVal(NULL)
  all_wind_u <- reactiveVal(NULL)
  all_wind_v <- reactiveVal(NULL)
  
  # Initial plot - only renders once
  output$animated_plot <- renderPlotly({
    req(rv$lats, rv$lons, rv$times)
    data <- get_variable_data()
    req(data)
    
    # Store data for later use
    all_plot_data(data)
    
    # If wind speed, also load U and V components for arrows
    if (input$variable == "Wind_Speed_10m") {
      u_data <- get_wind_component("U10")
      v_data <- get_wind_component("V10")
      all_wind_u(u_data)
      all_wind_v(v_data)
    } else {
      all_wind_u(NULL)
      all_wind_v(NULL)
    }
    
    has_multiple_times <- length(dim(data)) == 3 && dim(data)[1] > 1
    z_data <- if (has_multiple_times) data[1,,] else data
    
    # Convert PSFC to hPa before calculating range
    if (input$variable == "PSFC") {
      data <- data / 100
      z_data <- z_data / 100
    }
    
    data_range <- range(data, na.rm = TRUE)
    zmin <- data_range[1]
    zmax <- data_range[2]
    
    palette_name <- input$color_palette
    colors <- if (palette_name %in% c("viridis", "plasma", "magma", "inferno", "cividis", "turbo")) {
      viridis_pal(option = palette_name)(256)
    } else {
      colorRampPalette(RColorBrewer::brewer.pal(11, palette_name))(256)
    }
    if (input$reverse_colors) colors <- rev(colors)
    
    colorscale_list <- lapply(seq(0, 1, length.out = 256), function(i) {
      list(i, colors[round(i * 255) + 1])
    })
    
    var_labels <- list(
      Wind_Speed_10m = c("m/s", "10m Wind Speed & Direction"),
      Total_Precip = c("mm", "Total Precipitation"),
      PSFC = c("hPa", "Surface Pressure")
    )
    
    if (input$variable %in% names(var_labels)) {
      units <- var_labels[[input$variable]][1]
      long_name <- var_labels[[input$variable]][2]
    } else {
      var_info <- rv$first_nc$var[[input$variable]]
      units <- if(!is.null(var_info$units)) var_info$units else ""
      long_name <- if(!is.null(var_info$longname)) var_info$longname else input$variable
    }
    
    lon_range <- range(rv$lons)
    lat_range <- range(rv$lats)
    lon_pad <- diff(lon_range) * 0.02
    lat_pad <- diff(lat_range) * 0.02
    
    p <- plot_ly()
    has_borders <- FALSE
    border_data <- NULL
    
    if (requireNamespace("maps", quietly = TRUE)) {
      world_map <- maps::map("world", 
                             xlim = c(lon_range[1] - 5, lon_range[2] + 5),
                             ylim = c(lat_range[1] - 5, lat_range[2] + 5),
                             plot = FALSE, fill = FALSE)
      border_data <- list(lon = world_map$x, lat = world_map$y)
      has_borders <- TRUE
      
      p <- p %>%
        add_trace(x = border_data$lon, y = border_data$lat, type = "scatter", mode = "lines",
                  line = list(color = "gray50", width = 1), hoverinfo = "skip",
                  showlegend = FALSE, name = "borders")
    }
    
    p <- p %>%
      add_trace(
        lon = rv$lons, lat = rv$lats, z = z_data, type = "contour",
        zmin = zmin, zmax = zmax, zauto = FALSE,
        colorscale = colorscale_list,
        colorbar = list(title = units),
        contours = list(
          coloring = "heatmap",
          showlabels = FALSE,
          showlines = FALSE
        ),
        hovertemplate = paste0("Lon: %{lon:.2f}<br>Lat: %{lat:.2f}<br>", long_name, ": %{z:.2f}<br><extra></extra>"),
        showlegend = FALSE, name = "data"
      )
    
    # Add wind arrows if this is wind speed
    if (input$variable == "Wind_Speed_10m") {
      u_comp <- all_wind_u()
      v_comp <- all_wind_v()
      
      if (!is.null(u_comp) && !is.null(v_comp)) {
        u_data <- if (has_multiple_times) u_comp[1,,] else u_comp
        v_data <- if (has_multiple_times) v_comp[1,,] else v_comp
        
        # Subsample grid (every Nth point for arrows)
        skip <- max(1, floor(min(nrow(rv$lats), ncol(rv$lats)) / 20))
        arrow_rows <- seq(1, nrow(rv$lats), by = skip)
        arrow_cols <- seq(1, ncol(rv$lats), by = skip)
        
        arrow_lons <- as.vector(rv$lons[arrow_rows, arrow_cols])
        arrow_lats <- as.vector(rv$lats[arrow_rows, arrow_cols])
        arrow_u <- as.vector(u_data[arrow_rows, arrow_cols])
        arrow_v <- as.vector(v_data[arrow_rows, arrow_cols])
        
        # Calculate wind direction from u,v components (meteorological convention)
        wind_dir <- (270 - atan2(arrow_v, arrow_u) * 180 / pi) %% 360
        
        # Convert direction to unit vector components - use PIXEL coordinates, not degrees
        dir_rad <- wind_dir * pi / 180
        arrow_dx <- cos(dir_rad) * 30
        arrow_dy <- sin(dir_rad) * 30
        
        # Add arrows
        for (i in 1:length(arrow_lons)) {
          p <- p %>%
            add_annotations(
              x = arrow_lons[i], y = arrow_lats[i],
              ax = arrow_dx[i], ay = arrow_dy[i],
              xref = "x", yref = "y", axref = "pixel", ayref = "pixel",
              showarrow = TRUE, arrowhead = 2, arrowsize = 1,
              arrowwidth = 1.5, arrowcolor = "white", opacity = 0.8, text = ""
            )
        }
      }
    }
    
    p <- p %>%
      layout(
        title = paste(long_name, "-", strftime(rv$times[1], "%Y-%m-%d %H:%M", tz = "UTC")),
        xaxis = list(title = "Longitude", range = c(lon_range[1] - lon_pad, lon_range[2] + lon_pad), constrain = "domain"),
        yaxis = list(title = "Latitude", range = c(lat_range[1] - lat_pad, lat_range[2] + lat_pad), 
                     constrain = "domain", scaleanchor = "x"),
        plot_bgcolor = "lightblue", paper_bgcolor = "white"
      )
    
    p
  })
  
  # Use plotlyProxy to update only the data when time_step changes
  observeEvent(input$time_step, {
    data <- all_plot_data()
    req(data, rv$times)
    
    has_multiple_times <- length(dim(data)) == 3 && dim(data)[1] > 1
    if (!has_multiple_times) return()
    
    time_idx <- input$time_step
    z_data <- data[time_idx,,]
    
    # Convert PSFC to hPa for animation updates
    if (input$variable == "PSFC") {
      z_data <- z_data / 100
    }
    
    var_labels <- list(
      Wind_Speed_10m = c("m/s", "10m Wind Speed & Direction"),
      Total_Precip = c("mm", "Total Precipitation"),
      PSFC = c("hPa", "Surface Pressure")
    )
    
    if (input$variable %in% names(var_labels)) {
      long_name <- var_labels[[input$variable]][2]
    } else {
      var_info <- rv$first_nc$var[[input$variable]]
      long_name <- if(!is.null(var_info$longname)) var_info$longname else input$variable
    }
    
    # Determine trace index (1 if borders exist, 0 otherwise)
    trace_idx <- if (requireNamespace("maps", quietly = TRUE)) 1 else 0
    
    # Prepare relayout updates
    relayout_update <- list(
      title = paste(long_name, "-", strftime(rv$times[time_idx], "%Y-%m-%d %H:%M", tz = "UTC"))
    )
    
    # Update wind arrows if this is wind speed
    if (input$variable == "Wind_Speed_10m") {
      u_comp <- all_wind_u()
      v_comp <- all_wind_v()
      
      if (!is.null(u_comp) && !is.null(v_comp)) {
        u_data <- u_comp[time_idx,,]
        v_data <- v_comp[time_idx,,]
        
        # Subsample for arrows
        skip <- max(1, floor(min(nrow(rv$lats), ncol(rv$lats)) / 20))
        arrow_rows <- seq(1, nrow(rv$lats), by = skip)
        arrow_cols <- seq(1, ncol(rv$lats), by = skip)
        
        arrow_lons <- as.vector(rv$lons[arrow_rows, arrow_cols])
        arrow_lats <- as.vector(rv$lats[arrow_rows, arrow_cols])
        arrow_u <- as.vector(u_data[arrow_rows, arrow_cols])
        arrow_v <- as.vector(v_data[arrow_rows, arrow_cols])
        
        # Calculate wind direction from u,v components
        wind_dir <- (270 - atan2(arrow_v, arrow_u) * 180 / pi) %% 360
        
        # Convert to unit vector components - use PIXEL coordinates
        dir_rad <- wind_dir * pi / 180
        arrow_dx <- cos(dir_rad) * 30
        arrow_dy <- sin(dir_rad) * 30
        
        # Create annotations
        annotations <- lapply(1:length(arrow_lons), function(i) {
          list(
            x = arrow_lons[i], y = arrow_lats[i],
            ax = arrow_dx[i], ay = arrow_dy[i],
            xref = "x", yref = "y", axref = "pixel", ayref = "pixel",
            showarrow = TRUE, arrowhead = 2, arrowsize = 1,
            arrowwidth = 1.5, arrowcolor = "white", opacity = 0.8
          )
        })
        
        relayout_update$annotations <- annotations
      }
    }
    
    # Update the plot
    plotlyProxy("animated_plot", session) %>%
      plotlyProxyInvoke("restyle", list(z = list(t(z_data))), trace_idx) %>%
      plotlyProxyInvoke("relayout", relayout_update)
  })
  
  output$plot_ui <- renderUI({
    plotlyOutput("animated_plot", height = paste0(input$plot_height, "px"))
  })
  
  output$forecast_info <- renderText({
    req(rv$loaded_files, rv$times)
    paste(
      "Loaded Files:", nrow(rv$loaded_files), "\n",
      "Domain:", input$forecast_domain, "\n",
      "Forecast Date:", input$forecast_date, "\n",
      "Initial Hour:", sprintf("%02d:00", as.integer(input$forecast_hour)), "\n",
      "Time Steps:", length(rv$times), "\n",
      "Forecast Range:", strftime(rv$times[1], "%Y-%m-%d %H:%M", tz = "UTC"), "to",
      strftime(rv$times[length(rv$times)], "%Y-%m-%d %H:%M", tz = "UTC"), "\n",
      "Grid Size:", nrow(rv$lats), "x", ncol(rv$lats)
    )
  })
  
  output$var_stats <- renderText({
    data <- get_variable_data()
    req(data)
    
    var_units <- list(
      Wind_Speed_10m = c("m/s", "Wind_Speed_Direction_10m"),
      Total_Precip = c("mm", "Total_Precip"),
      PSFC = c("hPa", "PSFC")
    )
    
    if (input$variable %in% names(var_units)) {
      units <- var_units[[input$variable]][1]
      var_name <- var_units[[input$variable]][2]
      # Convert PSFC from Pa to hPa for stats
      if (input$variable == "PSFC") {
        data <- data / 100
      }
    } else {
      var_info <- rv$first_nc$var[[input$variable]]
      units <- if(!is.null(var_info$units)) var_info$units else ""
      var_name <- input$variable
    }
    
    stats <- paste(
      "Variable:", var_name, "\n", "Units:", units, "\n",
      "Min:", round(min(data, na.rm = TRUE), 3), "\n",
      "Max:", round(max(data, na.rm = TRUE), 3), "\n",
      "Mean:", round(mean(data, na.rm = TRUE), 3), "\n",
      "Std Dev:", round(sd(as.vector(data), na.rm = TRUE), 3)
    )
    stats
  })
  
  observeEvent(input$extract_point, {
    req(rv$lats, rv$lons, input$point_lat, input$point_lon, rv$loaded_files)
    
    withProgress(message = 'Extracting time series...', {
      dist <- sqrt((rv$lats - input$point_lat)^2 + (rv$lons - input$point_lon)^2)
      idx <- which(dist == min(dist), arr.ind = TRUE)
      sn_idx <- idx[1]
      we_idx <- idx[2]
      
      if (input$variable == "Total_Precip") {
        time_series <- sapply(1:nrow(rv$loaded_files), function(i) {
          nc <- nc_open(rv$loaded_files$path[i])
          rainc <- ncvar_get(nc, "RAINC")
          rainnc <- ncvar_get(nc, "RAINNC")
          
          if (length(dim(rainc)) == 3) {
            rainc <- rainc[1, sn_idx, we_idx]
            rainnc <- rainnc[1, sn_idx, we_idx]
          } else {
            rainc <- rainc[sn_idx, we_idx]
            rainnc <- rainnc[sn_idx, we_idx]
          }
          
          if (i != 1) nc_close(nc)
          rainc + rainnc
        })
      } else if (grepl("^Wind_", input$variable)) {
        u_var <- "U10"
        v_var <- "V10"
        
        time_series <- sapply(1:nrow(rv$loaded_files), function(i) {
          nc <- nc_open(rv$loaded_files$path[i])
          u_info <- nc$var[[u_var]]
          u_dims <- sapply(u_info$dim, function(d) d$name)
          
          start <- rep(1, length(u_dims))
          start[u_dims == "south_north"] <- sn_idx
          start[u_dims == "west_east"] <- we_idx
          
          u_val <- ncvar_get(nc, u_var, start = start, count = rep(1, length(u_dims)))
          v_val <- ncvar_get(nc, v_var, start = start, count = rep(1, length(u_dims)))
          
          if (i != 1) nc_close(nc)
          
          if (grepl("Speed", input$variable)) sqrt(u_val^2 + v_val^2) 
          else (atan2(u_val, v_val) * 180 / pi + 180) %% 360
        })
      } else {
        var_info <- rv$first_nc$var[[input$variable]]
        var_dims <- sapply(var_info$dim, function(d) d$name)
        
        time_series <- sapply(1:nrow(rv$loaded_files), function(i) {
          nc <- nc_open(rv$loaded_files$path[i])
          start <- rep(1, length(var_dims))
          
          start[var_dims == "south_north"] <- sn_idx
          start[var_dims == "west_east"] <- we_idx
          if ("south_north_stag" %in% var_dims) start[var_dims == "south_north_stag"] <- sn_idx
          if ("west_east_stag" %in% var_dims) start[var_dims == "west_east_stag"] <- we_idx
          
          value <- ncvar_get(nc, input$variable, start = start, count = rep(1, length(var_dims)))
          if (i != 1) nc_close(nc)
          value
        })
        
        # Convert PSFC from Pa to hPa
        if (input$variable == "PSFC") {
          time_series <- time_series / 100
        }
      }
      
      rv$point_data <- data.frame(
        time = rv$times, value = time_series,
        lat = rv$lats[sn_idx, we_idx], lon = rv$lons[sn_idx, we_idx]
      )
      
      showNotification(
        paste("Extracted time series at:", round(rv$point_data$lat[1], 3), ",", round(rv$point_data$lon[1], 3)),
        type = "message")
    })
  })
  
  output$timeseries_plot <- renderPlotly({
    req(rv$point_data)
    
    var_labels <- list(
      Wind_Speed_10m = c("m/s", "10m Wind Speed & Direction"),
      Total_Precip = c("mm", "Total Precipitation"),
      PSFC = c("hPa", "Surface Pressure")
    )
    
    if (input$variable %in% names(var_labels)) {
      units <- var_labels[[input$variable]][1]
      long_name <- var_labels[[input$variable]][2]
    } else {
      var_info <- rv$first_nc$var[[input$variable]]
      units <- if(!is.null(var_info$units)) var_info$units else ""
      long_name <- if(!is.null(var_info$longname)) var_info$longname else input$variable
    }
    
    plot_ly(rv$point_data, x = ~time, y = ~value, type = "scatter", mode = "lines+markers") %>%
      layout(
        title = paste(long_name, "at (", round(rv$point_data$lat[1], 3), ",", round(rv$point_data$lon[1], 3), ")"),
        xaxis = list(title = "Forecast Time"),
        yaxis = list(title = paste(long_name, "[", units, "]"))
      )
  })
  
  session$onSessionEnded(function() {
    if (!is.null(rv$first_nc)) nc_close(rv$first_nc)
  })
}

shinyApp(ui = ui, server = server)
