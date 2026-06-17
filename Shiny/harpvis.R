library(shiny)
library(harpVis)
library(harp)
library(dplyr)
library(RSQLite)


# ── Shiny options ──────────────────────────────────────────────────────────────
shinyOptions(
  app_start_dir = "/wrf/WRF_Model/Verification/Results",
  full_dir_navigation = TRUE,
  online              = TRUE,
  theme               = "white"
)

# ── Resource paths ─────────────────────────────────────────────────────────────
app_dir <- system.file("shiny_apps/plot_point_verif", package = "harpVis")
shiny::addResourcePath("harpvis-www", file.path(app_dir, "www"))
shiny::addResourcePath("harpvis-css", app_dir)

# ── Source base server from harpVis (Dashboard + Interactive tabs) ─────────────
old_wd <- getwd()
setwd(app_dir)
base_server <- source("server.R", local = TRUE)$value
setwd(old_wd)

# ── Data paths ─────────────────────────────────────────────────────────────────
fcst_dir <- "/wrf/WRF_Model/Verification/SQlite_tables/FCtables"
obs_dir  <- "/wrf/WRF_Model/Verification/SQlite_tables/Obs"

# ── Moisture helpers ───────────────────────────────────────────────────────────
.es         <- function(t) 611.2 * exp(17.67 * (t - 273.15) / (t - 29.65))
.eps        <- 287.05 / 461.5
.td_from_q  <- function(q, t, p) {
  e <- (q * p) / (.eps + q * (1 - .eps)); e[e <= 0] <- NA
  243.5 * log(e / 611.2) / (17.67 - log(e / 611.2))   # result in degC
}
.rh_from_q  <- function(q, t, p) {
  e <- (q * p) / (.eps + q * (1 - .eps))
  pmin(pmax(100 * e / .es(t), 0), 100)
}

# Column carrying forecast values in a harp_det_point_df
.fcst_col <- function(df) {
  meta <- c("SID","valid_dttm","lead_time","fcst_dttm","fcst_cycle",
            "units","fcst_model","parameter","z")
  setdiff(names(df), meta)[1]
}

# ── Directory-scanning helpers for dynamic UI dropdowns ────────────────────────

# Available model names (subdirectories of fcst_dir)
scan_models <- function() {
  dirs <- list.dirs(fcst_dir, full.names = FALSE, recursive = FALSE)
  sort(dirs[nchar(dirs) > 0])
}

# All distinct forecast start times (epoch → YYYYMMDDHH) found in SQLite files
# for the given param and models.
scan_fcst_dttms <- function(param, models) {
  if (length(models) == 0) return(character(0))
  fcst_param <- switch(param, td2m = "q2m", rh2m = "q2m", pcp_accum = "pcp", param)
  epoch_vals <- numeric(0)
  for (model in models) {
    files <- list.files(
      file.path(fcst_dir, model),
      pattern    = paste0("FCTABLE_", fcst_param, "_[0-9]{6}_[0-9]{2}\\.sqlite"),
      recursive  = TRUE,
      full.names = TRUE
    )
    for (f in files) {
      tryCatch({
        con  <- dbConnect(SQLite(), f)
        tbls <- dbListTables(con)
        tbl  <- if ("FC" %in% tbls) "FC" else if (length(tbls) > 0) tbls[1] else NA_character_
        if (!is.na(tbl)) {
          res        <- dbGetQuery(con, paste0("SELECT DISTINCT fcst_dttm FROM \"", tbl, "\""))
          epoch_vals <- c(epoch_vals, as.numeric(res[[1]]))
        }
        dbDisconnect(con)
      }, error = function(e) NULL)
    }
  }
  if (length(epoch_vals) == 0) return(character(0))
  epoch_vals <- sort(unique(epoch_vals))
  # Keep only dates for which an obs file also exists
  obs_files  <- list.files(obs_dir, pattern = "^obstable_[0-9]{6}\\.sqlite$")
  obs_months <- sub("^obstable_([0-9]{6})\\.sqlite$", "\\1", obs_files)
  dt         <- as.POSIXct(epoch_vals, origin = "1970-01-01", tz = "UTC")
  has_obs    <- format(dt, "%Y%m") %in% obs_months
  epoch_vals <- epoch_vals[has_obs]
  dt         <- dt[has_obs]
  if (length(epoch_vals) == 0) return(character(0))
  vals <- format(dt, "%Y%m%d%H")
  nms  <- format(dt, "%Y-%m-%d %H:00 UTC")
  setNames(vals, nms)
}

# Distinct station IDs for a given param + models + forecast start time string.
scan_stations <- function(param, models, fcst_dttm_str) {
  if (length(models) == 0 || is.null(fcst_dttm_str) || nchar(fcst_dttm_str) == 0)
    return(integer(0))
  fcst_param <- switch(param, td2m = "q2m", rh2m = "q2m", pcp_accum = "pcp", param)
  fcst_dt    <- as.POSIXct(fcst_dttm_str, format = "%Y%m%d%H", tz = "UTC")
  epoch_dt   <- as.numeric(fcst_dt)
  yyyymm     <- format(fcst_dt, "%Y%m")
  yyyy       <- format(fcst_dt, "%Y")
  mm         <- format(fcst_dt, "%m")
  hh         <- format(fcst_dt, "%H")
  sids <- integer(0)
  for (model in models) {
    f <- file.path(fcst_dir, model, yyyy, mm,
                   paste0("FCTABLE_", fcst_param, "_", yyyymm, "_", hh, ".sqlite"))
    if (!file.exists(f)) next
    tryCatch({
      con  <- dbConnect(SQLite(), f)
      tbls <- dbListTables(con)
      tbl  <- if ("FC" %in% tbls) "FC" else if (length(tbls) > 0) tbls[1] else NA_character_
      if (!is.na(tbl)) {
        res  <- dbGetQuery(con,
          paste0("SELECT DISTINCT SID FROM \"", tbl, "\" WHERE fcst_dttm = ", epoch_dt)
        )
        sids <- c(sids, res[[1]])
      }
      dbDisconnect(con)
    }, error = function(e) NULL)
  }
  sids <- sort(unique(sids))
  # Look up station names from local stationlist.csv and label as "Name (SID)"
  sl <- tryCatch(
    read.csv("/wrf/WRF_Model/Verification/Data/Static/stationlist.csv",
             stringsAsFactors = FALSE),
    error = function(e) NULL
  )
  if (!is.null(sl) && "name" %in% names(sl) && "SID" %in% names(sl)) {
    matched <- sl[sl$SID %in% sids, c("SID", "name")]
    labels  <- ifelse(
      sids %in% matched$SID,
      paste0(matched$name[match(sids, matched$SID)], " (", sids, ")"),
      as.character(sids)
    )
    setNames(sids, labels)
  } else {
    sids
  }
}

# ── Read raw forecasts + obs, join, return list(data, obs_col) ─────────────────
read_ts_data <- function(param, models, fcst_dt, lead_max) {
  leads <- seq(0, lead_max, by = 1)

  read_fcst <- function(p) {
    tryCatch(
      read_point_forecast(
        dttm          = fcst_dt,
        fcst_model    = models,
        fcst_type     = "det",
        parameter     = p,
        file_path     = fcst_dir,
        file_template = paste0("{fcst_model}/{YYYY}/{MM}/FCTABLE_", p, "_{YYYY}{MM}_{HH}.sqlite"),
        lead_time     = leads
      ),
      error = function(e) NULL
    )
  }

  obs_param <- NULL
  obs_col   <- NULL

  if (param %in% c("td2m", "rh2m")) {
    hl_q <- read_fcst("q2m")
    hl_t <- read_fcst("t2m")
    hl_p <- read_fcst("psfc")
    if (is.null(hl_q)) stop("Could not read q2m forecast data")
    if (is.null(hl_t)) stop("Could not read t2m forecast data")
    if (is.null(hl_p)) stop("Could not read psfc forecast data")

    derive_fn <- if (param == "td2m") .td_from_q else .rh_from_q
    obs_param <- if (param == "td2m") "Td2m" else "RH2m"
    obs_col   <- obs_param
    units_out <- if (param == "td2m") "degC" else "percent"

    fcst_hl <- setNames(lapply(models, function(m) {
      q_df <- hl_q[[m]]; t_df <- hl_t[[m]]; p_df <- hl_p[[m]]
      if (is.null(q_df) || is.null(t_df) || is.null(p_df)) return(NULL)
      q_col <- .fcst_col(q_df); t_col <- .fcst_col(t_df); p_col <- .fcst_col(p_df)
      aux <- inner_join(
        select(q_df, SID, valid_dttm, lead_time, fcst_dttm, q = all_of(q_col)),
        select(t_df, SID, valid_dttm, lead_time, fcst_dttm, t = all_of(t_col)),
        by = c("SID", "valid_dttm", "lead_time", "fcst_dttm")
      ) |> inner_join(
        select(p_df, SID, valid_dttm, lead_time, fcst_dttm, p = all_of(p_col)),
        by = c("SID", "valid_dttm", "lead_time", "fcst_dttm")
      )
      result <- inner_join(q_df,
        select(aux, SID, valid_dttm, lead_time, fcst_dttm, q, t, p),
        by = c("SID", "valid_dttm", "lead_time", "fcst_dttm")
      ) |>
        mutate(!!q_col := derive_fn(as.numeric(q), as.numeric(t), as.numeric(p))) |>
        select(-q, -t, -p)
      result$units     <- units_out
      result$parameter <- param
      result
    }), models)

  } else {
    fcst_param <- switch(param,
      t2m       = "t2m",  psfc      = "psfc", ws10m     = "ws10m",
      q2m       = "q2m",  pcp       = "pcp",  pcp_accum = "pcp",
      stop("Unknown parameter: ", param)
    )
    obs_param <- switch(param,
      t2m       = "T2m",  psfc      = "Ps",   ws10m     = "S10m",
      q2m       = "Q2m",  pcp       = "AccPcp1h", pcp_accum = "AccPcp1h"
    )
    obs_col <- obs_param

    fcst_hl <- read_fcst(fcst_param)
    if (is.null(fcst_hl)) stop("Could not read forecast data for '", param, "'")

    # Convert cumulative pcp (from forecast start) to 1-hour increments,
    # matching the logic used in verify_parameters.R and the obs AccPcp1h values.
    diff_pcp <- function(hl) {
      lapply(as.list(hl), function(df) {
        if (is.null(df) || !is.data.frame(df) || nrow(df) == 0) return(df)
        fc <- .fcst_col(df)
        if (is.null(fc) || is.na(fc)) return(df)
        df  <- df[order(df$SID, as.numeric(df$fcst_dttm), df$lead_time), ]
        grp <- paste(df$SID, as.numeric(df$fcst_dttm), sep = "_")
        df[[fc]] <- ave(df[[fc]], grp, FUN = function(v) {
          d <- c(v[1], diff(v))
          ifelse(d < 0, v, d)   # guard against negative diffs from rounding
        })
        df
      })
    }

    fcst_hl <- switch(param,
      t2m       = scale_param(fcst_hl, -273.15, "degC"),
      psfc      = scale_param(fcst_hl,  0.01,   "hPa", mult = TRUE),
      ws10m     = set_units(fcst_hl, "m/s"),
      pcp       = ,
      pcp_accum = diff_pcp(set_units(fcst_hl, "mm")),
      fcst_hl
    )
    fcst_hl <- as.list(fcst_hl)   # strip to plain list for uniform handling below
  }

  # Drop models with no data
  fcst_hl <- Filter(function(x) !is.null(x) && is.data.frame(x) && nrow(x) > 0, fcst_hl)
  if (length(fcst_hl) == 0) stop("No forecast data found for any of the requested models")
  fcst_hl <- as_harp_list(fcst_hl)

  # Read observations
  all_valid <- unique_valid_dttm(fcst_hl)
  all_sids  <- unique_stations(fcst_hl)
  obs <- tryCatch(
    read_point_obs(
      dttm             = all_valid,
      parameter        = obs_param,
      stations         = all_sids,
      obs_path         = obs_dir,
      obsfile_template = "obstable_{YYYY}{MM}.sqlite"
    ),
    error = function(e) NULL
  )
  if (is.null(obs) || nrow(obs) == 0) {
    avail_files <- list.files(obs_dir, pattern = "obstable_[0-9]{6}\\.sqlite$")
    avail_months <- sort(sub("obstable_([0-9]{6})\\.sqlite", "\\1", avail_files))
    avail_str <- if (length(avail_months) > 0)
      paste(avail_months, collapse = ", ")
    else
      "none"
    stop("No observations found for '", obs_param, "' for the selected forecast start (",
         format(fcst_dt, "%Y-%m-%d %H:00 UTC"), ").\n",
         "Available observation months: ", avail_str, ".\n",
         "Please select a forecast start date within those months.")
  }

  joined <- fcst_hl |> common_cases() |> join_to_fcst(obs)
  list(data = joined, obs_col = obs_col)
}

# Scan available models once at startup
available_models <- scan_models()

# ── Theming ────────────────────────────────────────────────────────────────────
app_theme <- shiny::getShinyOption("theme", default = "white")
css_href  <- paste0("harpvis-css/", switch(app_theme,
  "dark"  = "harp_midnight.css",
  "light" = "harp_light.css",
  "harp_white.css"
))
is_online <- shiny::getShinyOption("online", default = TRUE)
font_link <- if (isTRUE(is_online) && !grepl("^ecgb", Sys.getenv("HOSTNAME"))) {
  shiny::tags$link(
    href = "https://fonts.googleapis.com/css?family=Comfortaa:400,700",
    rel  = "stylesheet"
  )
} else {
  shiny::tags$link("")
}

# ── UI ─────────────────────────────────────────────────────────────────────────
# Rebuild the harpVis UI directly (mirrors the bundled ui.R) so we can inject
# the new Time Series tab without modifying the package files.
ui <- shiny::tags$html(
  shiny::tags$head(
    font_link,
    shiny::tags$link(rel = "stylesheet", href = css_href)
  ),
  shiny::tags$body(
    shiny::tags$div(
      class = "harp_page_header",
      shiny::span(class = "harp_page_title", "harp : : Point Verification"),
      shiny::div(class = "harp_logo",
        shiny::img(src = "harpvis-www/harp_logo_dark.svg", height = "70px")
      )
    ),
    shiny::fluidPage(
      title = "harp",
      harpVis::options_barUI("options_bar"),
      shiny::fluidRow(harpVis::group_selectorsUI("group_selectors")),
      shiny::fluidRow(
        harpVis::time_axisUI("time_axis"),
        harpVis::colour_choicesUI("colour_choices")
      ),
      shiny::tabsetPanel(id = "tab_panel",

        shiny::tabPanel("Dashboard",
          harpVis::dashboard_point_verifUI("dashboard")
        ),

        shiny::tabPanel("Interactive",
          harpVis::interactive_point_verifUI("interactive"),
          harpVis::download_verif_plotUI("download_plot")
        ),

        shiny::tabPanel("Time Series",
          shiny::br(),
          shiny::fluidRow(
            shiny::column(3,
              shiny::wellPanel(
                shiny::selectInput("ts_param", "Parameter",
                  choices = c(
                    "Temperature (2m)"        = "t2m",
                    "Surface Pressure"        = "psfc",
                    "Wind Speed (10m)"        = "ws10m",
                    "Dew Point (2m)"          = "td2m",
                    "Relative Humidity (2m)"  = "rh2m",
                    "Specific Humidity (2m)"  = "q2m",
                    "Precipitation (1h acc.)"     = "pcp",
                    "Precipitation (total accum.)" = "pcp_accum"
                  )
                ),
                shiny::selectInput("ts_models", "Models",
                  choices  = available_models,
                  selected = available_models,
                  multiple = TRUE
                ),
                shiny::selectInput("ts_fcst_dttm", "Forecast start",
                  choices = character(0)
                ),
                shiny::selectInput("ts_station", "Station(s)",
                  choices  = character(0),
                  multiple = TRUE
                ),
                shiny::selectInput("ts_x_axis", "X axis",
                  choices  = c("Valid time" = "valid_dttm", "Lead time (h)" = "lead_time"),
                  selected = "valid_dttm"
                ),
                shiny::numericInput("ts_lead_max", "Max lead time (h)",
                  value = 48, min = 6, max = 240, step = 6
                ),
                shiny::actionButton("ts_plot_btn", "Plot", class = "btn-primary")
              )
            ),
            shiny::column(9,
              shiny::uiOutput("ts_status"),
              shiny::plotOutput("ts_plot", height = "500px")
            )
          )
        ) # end Time Series tab

      ) # end tabsetPanel
    ) # end fluidPage
  ) # end body
) # end html

# ── Server ─────────────────────────────────────────────────────────────────────
server <- function(input, output, session) {

  # Delegate to harpVis base server (Dashboard + Interactive tabs)
  base_server(input, output, session)

  # ── Time Series ─────────────────────────────────────────────────────────────
  ts_error <- shiny::reactiveVal(NULL)

  # Update forecast-date choices whenever param or models selection changes
  shiny::observe({
    param  <- input$ts_param
    models <- input$ts_models
    shiny::req(length(models) > 0)
    choices <- scan_fcst_dttms(param, models)
    shiny::updateSelectInput(session, "ts_fcst_dttm",
      choices  = choices,
      selected = if (length(choices) > 0) choices[[length(choices)]] else character(0)
    )
  })

  # Update station choices whenever param, models, or date changes
  shiny::observe({
    param     <- input$ts_param
    models    <- input$ts_models
    fcst_dttm <- input$ts_fcst_dttm
    shiny::req(length(models) > 0, !is.null(fcst_dttm), nchar(fcst_dttm) > 0)
    sids <- scan_stations(param, models, fcst_dttm)
    shiny::updateSelectInput(session, "ts_station",
      choices  = sids,
      selected = character(0)
    )
  })

  ts_result <- shiny::eventReactive(input$ts_plot_btn, {
    ts_error(NULL)
    shiny::req(
      length(input$ts_models)   > 0,
      length(input$ts_fcst_dttm) > 0,
      length(input$ts_station)  > 0
    )
    models  <- input$ts_models
    fcst_dt <- as.POSIXct(input$ts_fcst_dttm, format = "%Y%m%d%H", tz = "UTC")

    result <- tryCatch(
      shiny::withProgress(message = "Reading data...", value = 0.5,
        read_ts_data(input$ts_param, models, fcst_dt, input$ts_lead_max)
      ),
      error = function(e) { ts_error(e$message); NULL }
    )
    result
  })

  output$ts_status <- shiny::renderUI({
    msg <- ts_error()
    if (!is.null(msg))
      shiny::div(
        class = "alert alert-danger", style = "margin-top:10px;",
        shiny::strong("Error: "), msg
      )
  })
  output$ts_plot <- shiny::renderPlot({
    result <- ts_result()
    shiny::req(!is.null(result))

    sids_int    <- suppressWarnings(as.integer(input$ts_station))
    sids        <- if (all(!is.na(sids_int))) sids_int else input$ts_station
    ts_data     <- result$data
    obs_col_str <- result$obs_col
    x_var       <- input$ts_x_axis
    fcst_epoch  <- as.numeric(as.POSIXct(input$ts_fcst_dttm, format = "%Y%m%d%H", tz = "UTC"))

    # Combine harp_list into a flat long-format data frame
    # harpCore::bind pivots model-specific _det columns into fcst_model + fcst
    all_df <- tryCatch(
      as.data.frame(harpCore::bind(ts_data)),
      error = function(e) as.data.frame(dplyr::bind_rows(lapply(ts_data, as.data.frame)))
    )

    row_mask <- (
      as.character(all_df$SID) %in% as.character(sids) &
      abs(as.numeric(all_df$fcst_dttm) - fcst_epoch) < 1
    )
    plot_df <- all_df[which(row_mask), , drop = FALSE]
    shiny::validate(shiny::need(nrow(plot_df) > 0, "No data found for the selected stations/date."))

    # For total accumulated precip, cumsum 1h increments from forecast start
    if (isTRUE(input$ts_param == "pcp_accum")) {
      plot_df <- plot_df |>
        dplyr::arrange(SID, fcst_model, lead_time) |>
        dplyr::group_by(SID, fcst_model) |>
        dplyr::mutate(
          fcst              = cumsum(ifelse(is.na(fcst), 0, fcst)),
          !!obs_col_str    := cumsum(ifelse(is.na(.data[[obs_col_str]]), 0, .data[[obs_col_str]]))
        ) |>
        dplyr::ungroup()
    }
    y_label <- if (isTRUE(input$ts_param == "pcp_accum")) "Accum. Precip (mm)" else obs_col_str

    # Build forecast lines (one colour per model).
    # Observations are shown as a separate black line included in the legend
    # via a linetype scale ("Observed" label).
    obs_label  <- "Observed"

    p <- ggplot2::ggplot(
        plot_df,
        ggplot2::aes(
          x      = .data[[x_var]],
          y      = fcst,
          colour = fcst_model,
          group  = interaction(fcst_model, SID)
        )
      ) +
      ggplot2::geom_line(linewidth = 0.8) +
      ggplot2::labs(colour = "Model", y = y_label) +
      tryCatch(harpVis::theme_harp_light(), error = function(e) ggplot2::theme_minimal())

    # Add observation line with its own linetype entry in the legend
    obs_cols <- intersect(c("SID", x_var, obs_col_str), names(plot_df))
    if (obs_col_str %in% obs_cols) {
      obs_df <- unique(plot_df[, obs_cols, drop = FALSE])
      obs_df <- obs_df[!is.na(obs_df[[obs_col_str]]), , drop = FALSE]
      if (nrow(obs_df) > 0) {
        p <- p +
          ggplot2::geom_line(
            data        = obs_df,
            mapping     = ggplot2::aes(
              x        = .data[[x_var]],
              y        = .data[[obs_col_str]],
              linetype = obs_label,
              group    = as.character(SID)
            ),
            colour      = "black",
            linewidth   = 1.2,
            inherit.aes = FALSE
          ) +
          ggplot2::scale_linetype_manual(
            name   = NULL,
            values = setNames("solid", obs_label),
            guide  = ggplot2::guide_legend(
              override.aes = list(colour = "black", linewidth = 1.2)
            )
          )
      }
    }

    # X-axis ticks every 3 hours
    if (x_var == "valid_dttm") {
      p <- p + ggplot2::scale_x_datetime(
        date_breaks = "3 hours",
        date_labels = "%d %b\n%H:00"
      )
    } else {
      # lead_time is numeric (hours); generate breaks every 3 h
      lt_range <- range(plot_df[[x_var]], na.rm = TRUE)
      p <- p + ggplot2::scale_x_continuous(
        breaks = seq(floor(lt_range[1] / 3) * 3, ceiling(lt_range[2] / 3) * 3, by = 3)
      )
    }

    # Facet by station when multiple stations are selected
    if (length(sids) > 1) {
      p <- p + ggplot2::facet_wrap(~SID, ncol = 1)
    }

    p
  })
}

shinyApp(ui = ui, server = server)