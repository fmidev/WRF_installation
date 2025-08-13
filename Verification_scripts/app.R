library(shiny)
library(harpVis)

# Set options for file navigation
shinyOptions(
  app_start_dir = system.file("verification", package = "harpVis"),
  full_dir_navigation = TRUE
)

ui <- fluidPage(
  fluidRow(
    column(12,
      # File loading interface
      options_barUI("file_opts")
    )
  ),
  fluidRow(
    column(12,
      # Dashboard output for point verification
      dashboard_point_verifUI("pt_dshbrd")
    )
  )
)

server <- function(input, output, session) {
  # Reactive: loaded verification data
  verif_data <- callModule(options_bar, "file_opts")
  
  # Example colour table for plotting (customize as needed)
  colour_table <- reactive({
    df <- verif_data()
    # Build a table matching the models in your data
    data.frame(
      fcst_model = unique(df$ens_summary_scores$fcst_model),
      colour = rainbow(length(unique(df$ens_summary_scores$fcst_model)))
    )
  })
  
  # Define time axis for the dashboard
  time_axis <- reactive("lead_time")
  
  # Call the point verification dashboard module
  callModule(
    dashboard_point_verif,
    "pt_dshbrd",
    reactive(verif_data()),
    reactive(colour_table()),
    time_axis
  )
}

shinyApp(ui, server)
