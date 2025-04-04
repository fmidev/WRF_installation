import csv
import sys

#Python script to convert CSV data to little_r format

#CSV data should have the following column names in the first row (no need to be in this order). 
#station_id,latitude,longitude,date,sea_level_pressure,pressure,height,temperature,wind_speed,wind_direction,relative_humidity

#All parameters are not mandatory but at least one of 'pressure' or 'height' must be provided in the CSV data.):




def convert_to_little_r(data, elevation):
    little_r_data = ""
    
    # Extract parameters from data
    xlat = float(data.get('latitude', -888888))
    xlon = float(data.get('longitude', -888888))
    date_char = data.get('date', '00000000000000')
    slp = float(data.get('sea_level_pressure', -888888))
    p = float(data.get('pressure', -888888))
    z = float(data.get('height', -888888))
    t = float(data.get('temperature', -888888))
    spd = float(data.get('wind_speed', -888888))
    direction = float(data.get('wind_direction', -888888))
    rh = float(data.get('relative_humidity', -888888))

    # Ensure at least one of p or z is available
    if p == -888888 and z == -888888:
        raise ValueError("At least one of 'pressure' or 'height' must be provided")

    # Example header
    header = (
        f"{xlat:20.5f}{xlon:20.5f}{'':<40}{'':<40}"
        f"{'':<40}{'':<40}{elevation:20.5f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}"
        f"{'F':<10}{'F':<10}{'F':<10}"
        f"{-888888:10.0f}{-888888:10.0f}{date_char:<20}{slp:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
        f"{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}{-888888:13.5f}{0:7.0f}"
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
        for row in csv_reader:
            station_id = row['station_id']
            elevation = float(row['elevation'])
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

