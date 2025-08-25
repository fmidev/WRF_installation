import csv
import sys
from datetime import datetime

#Python script to convert CSV data to little_r format

#CSV data should have the following column names in the first row (no need to be in this order). 
#station_id,latitude,longitude,date,sea_level_pressure,pressure,height,temperature,wind_speed,wind_direction,relative_humidity

#All parameters are not mandatory but at least one of 'pressure' or 'height' must be provided in the CSV data.):




def safe_float(val, default=-888888):
    try:
        if val is None or val == '':
            return default
        return float(val)
    except ValueError:
        return default

def format_little_r_date(date_str):
    # Try to parse date in the format 'YYYY-MM-DD HH:MM:SS_00:00:00'
    # If fails, fallback to '00000000000000'
    try:
        # Remove trailing _00:00:00 if present
        if '_' in date_str:
            date_str = date_str.split('_')[0]
        # Try parsing
        dt = datetime.strptime(date_str, "%Y-%m-%d %H:%M:%S")
        return dt.strftime("%Y%m%d%H%M%S")
    except Exception:
        return "00000000000000"

def convert_to_little_r(data, elevation):
    little_r_data = ""
    
    # Extract parameters from data using safe_float
    xlat = safe_float(data.get('latitude'))
    xlon = safe_float(data.get('longitude'))
    station_id = str(data.get('station_id', ''))
    platform_type = 'local'
    platform = 'FM-12'
    date_char = format_little_r_date(data.get('date', '00000000000000'))
    slp = safe_float(data.get('sea_level_pressure'))
    p = safe_float(data.get('pressure'))
    z = safe_float(data.get('height'))
    t = safe_float(data.get('temperature'))
    spd = safe_float(data.get('wind_speed'))
    direction = safe_float(data.get('wind_direction'))
    rh = safe_float(data.get('relative_humidity'))

    # Ensure at least one of p or z is available
    if p == -888888 and z == -888888:
        raise ValueError("At least one of 'pressure' or 'height' must be provided")

    # Example header
    header = (
        f"{xlat:20.5f}{xlon:20.5f}{station_id:<40}{platform_type:<40}"
        f"{platform:<40}{'':<40}{elevation:20.5f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}"
        f"{'F':<10}{'F':<10}{'F':<10}"
        f"{-888888:10.0f}{-888888:10.0f}{date_char:<20}{slp:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}\n"
    )
    little_r_data += header

    # Example report
    report = (
        f"{p:13.5f}{0:7.0f}{z:13.5f}{0:7.0f}{t:13.5f}{0:7.0f}{rh:13.5f}{0:7.0f}"
        f"{spd:13.5f}{0:7.0f}{direction:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}\n"
    )
    little_r_data += report

    # End of report line
    end_of_report = (
        f"{-777777:13.5f}{0:7.0f}{-777777:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}\n"
    )
    little_r_data += end_of_report

    # End of message line
    end_of_message = f"{10:7.0f}{0:7.0f}{0:7.0f}\n"
    little_r_data += end_of_message

    return little_r_data

def fetch_csv_data(file_path):
    data_list = []
    with open(file_path, mode='r') as file:
        csv_reader = csv.DictReader(file)
        for row in csv_reader:
            data_list.append(row)
    return data_list

def fetch_elevation_data(file_path):
    elevation_data = {}
    with open(file_path, mode='r') as file:
        csv_reader = csv.DictReader(file)
        # Support both 'station_id' and 'SID' as station id column
        sid_col = None
        elev_col = None
        for col in csv_reader.fieldnames:
            if col.lower() in ['station_id', 'sid']:
                sid_col = col
            if col.lower() in ['elevation', 'elev']:
                elev_col = col
        if sid_col is None or elev_col is None:
            raise ValueError("Station file must have a station id column ('station_id' or 'SID') and elevation column ('elevation' or 'elev')")
        for row in csv_reader:
            station_id = row[sid_col]
            elevation = float(row[elev_col])
            elevation_data[station_id] = elevation
    return elevation_data

def main():
    if len(sys.argv) != 4:
        print("Usage: python convert_to_little_r.py <data_file_path> <station_file_path> <output_file>")
        sys.exit(1)
    
    data_file_path = sys.argv[1]
    station_file_path = sys.argv[2]
    output_file = sys.argv[3]
    
    data_list = fetch_csv_data(data_file_path)
    elevation_data = fetch_elevation_data(station_file_path)
    
    with open(output_file, "w") as file:
        for data in data_list:
            station_id = data.get('station_id', 'unknown')
            elevation = elevation_data.get(station_id, -888888)
            little_r_data = convert_to_little_r(data, elevation)
            file.write(little_r_data)

if __name__ == "__main__":
    main()

