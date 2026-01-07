library(shiny)
library(harpVis)

# Set Shiny options
shinyOptions(
  app_start_dir = "/wrf/WRF_Model/Verification/Results",
  full_dir_navigation = TRUE,
  online = TRUE,
  theme = "white"
)

# Get the path to the harpVis shiny app
app_dir <- system.file("shiny_apps/plot_point_verif", package = "harpVis")

shiny::addResourcePath("harpvis-www", file.path(app_dir, "www"))
shiny::addResourcePath("harpvis-css", app_dir)

# Change to the app directory for sourcing files with relative paths
old_wd <- getwd()
setwd(app_dir)

# Source the UI and server from the harpVis package
source("ui.R", local = TRUE)
server_func <- source("server.R", local = TRUE)$value

# Restore original working directory
setwd(old_wd)

# Modify the UI to use the correct resource paths
ui_modified <- shiny::tagList(
  # Add the resource path prefix to images
  shiny::tags$head(
    shiny::tags$script(shiny::HTML("
      $(document).ready(function() {
        $('img[src=\"harp_logo_dark.svg\"]').attr('src', 'harpvis-www/harp_logo_dark.svg');
        $('img[src=\"harp_logo.svg\"]').attr('src', 'harpvis-www/harp_logo.svg');
      });
    "))
  ),
  ui
)

server <- server_func
shinyApp(ui = ui_modified, server = server)