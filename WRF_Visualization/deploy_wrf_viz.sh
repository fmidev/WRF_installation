#!/bin/bash
# ===============================================
# Deploy WRF Visualization App to Shiny Server
# ===============================================

# Shiny server apps directory
SHINY_APPS_DIR="/srv/shiny-server"
APP_NAME="wrf-viz"

# Source directory (where this script is located)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Deploying WRF Visualization App..."

# Check if Shiny Server directory exists
if [ ! -d "$SHINY_APPS_DIR" ]; then
    echo "Error: Shiny Server directory not found at $SHINY_APPS_DIR"
    echo "Is Shiny Server installed?"
    exit 1
fi

# Create app directory
echo "Creating app directory: $SHINY_APPS_DIR/$APP_NAME"
sudo mkdir -p "$SHINY_APPS_DIR/$APP_NAME"

# Copy the app file
echo "Copying app.R..."
sudo cp "$SCRIPT_DIR/wrf_viz_app.R" "$SHINY_APPS_DIR/$APP_NAME/app.R"

# Set proper permissions
echo "Setting permissions..."
sudo chown -R shiny:shiny "$SHINY_APPS_DIR/$APP_NAME"
sudo chmod -R 755 "$SHINY_APPS_DIR/$APP_NAME"

# Restart Shiny Server
echo "Restarting Shiny Server..."
sudo systemctl restart shiny-server

# Check if service is running
if sudo systemctl is-active --quiet shiny-server; then
    echo ""
    echo "✅ WRF Visualization App deployed successfully!"
    echo ""
    echo "Access the app at: http://localhost:3838/$APP_NAME/"
    echo ""
    echo "Note: Make sure the WRF output directory path in the app matches your setup."
else
    echo ""
    echo "❌ Error: Shiny Server failed to start. Check logs with:"
    echo "   sudo journalctl -u shiny-server -n 50"
fi
