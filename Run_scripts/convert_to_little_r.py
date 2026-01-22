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

def _get_first(data: dict, keys, default=None):
    """Return first non-empty value for any key in keys (case-insensitive)."""
    if not isinstance(data, dict):
        return default
    lower_map = {str(k).lower(): k for k in data.keys()}
    for key in keys:
        k = lower_map.get(str(key).lower())
        if k is None:
            continue
        v = data.get(k)
        if v is None:
            continue
        if isinstance(v, str) and v.strip() == "":
            continue
        return v
    return default


def format_little_r_date(date_str):
    """Format date as YYYYMMDDhhmmss for little_r format (A20 field).

    Accepts common formats seen in CSV feeds. Returns None if unparseable.
    """
    if date_str is None:
        return None
    date_str = str(date_str).strip()
    if date_str == "":
        return None

    if '_' in date_str:
        parts = date_str.split('_')
        # If last part looks like HH:MM:SS, treat underscore as date/time separator.
        if len(parts) == 2 and ":" in parts[1]:
            date_str = f"{parts[0]} {parts[1]}".strip()
        else:
            # Otherwise drop suffix after first underscore.
            date_str = parts[0].strip()

    # Common formats we can encounter
    fmts = [
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y/%m/%d %H:%M:%S",
        "%Y/%m/%d %H:%M",
        "%Y%m%d%H%M%S",
        "%Y%m%d%H%M",
        "%Y%m%d%H",
    ]
    for fmt in fmts:
        try:
            dt = datetime.strptime(date_str, fmt)
            # Return in little_r format: YYYYMMDDhhmmss (14 digits, numerical only)
            return dt.strftime("%Y%m%d%H%M%S")
        except Exception:
            pass

    # Last resort: try reading a leading 14-digit timestamp
    digits = "".join(ch for ch in date_str if ch.isdigit())
    if len(digits) >= 14:
        try:
            dt = datetime.strptime(digits[:14], "%Y%m%d%H%M%S")
            return dt.strftime("%Y%m%d%H%M%S")
        except Exception:
            pass
    return None

def convert_to_little_r(data, elevation):
    little_r_data = ""
    
    # Extract parameters from data using safe_float
    xlat = safe_float(_get_first(data, ['latitude', 'lat']))
    xlon = safe_float(_get_first(data, ['longitude', 'lon', 'long']))
    station_id = str(_get_first(data, ['station_id', 'sid', 'station', 'id'], '')).strip()
    platform_type = 'local'
    platform = 'FM-12'
    date_char = format_little_r_date(_get_first(data, ['date', 'datetime', 'time', 'valid_time']))
    
    # Extract raw values
    slp = safe_float(_get_first(data, ['sea_level_pressure', 'slp', 'mslp']))
    p = safe_float(_get_first(data, ['pressure', 'pres', 'p']))
    z = safe_float(_get_first(data, ['height', 'elevation_m', 'z']))
    t = safe_float(_get_first(data, ['temperature', 'temp', 't']))
    spd = safe_float(_get_first(data, ['wind_speed', 'wspd', 'spd']))
    direction = safe_float(_get_first(data, ['wind_direction', 'wdir', 'dir']))
    rh = safe_float(_get_first(data, ['relative_humidity', 'rh']))
    
    # Unit conversions for little_r format:
    # Pressure: hPa -> Pa (multiply by 100)
    # Detect if pressure is in hPa (typical range 500-1100) or already in Pa (50000-110000)
    if p != -888888:
        if p < 2000:  # Likely in hPa
            p = p * 100.0
    if slp != -888888:
        if slp < 2000:  # Likely in hPa
            slp = slp * 100.0
    
    # Temperature: Celsius -> Kelvin (add 273.15)
    # Detect if temperature is in Celsius (typical range -100 to 60) or already in Kelvin (173-333)
    if t != -888888:
        if t < 100:  # Likely in Celsius (could be negative)
            t = t + 273.15

    # Ensure at least one of p or z is available
    if p == -888888 and z == -888888:
        raise ValueError("At least one of 'pressure' or 'height' must be provided")

    # Date is required for obsproc/time-windowing.
    if not date_char:
        raise ValueError("Missing or unparseable 'date' in input row; refusing to write invalid date")

    if station_id == "":
        # obsproc can still ingest, but IDs help matching/diagnostics.
        station_id = "UNKNOWN"

    # Little_r format header - date field must be exactly 20 characters (A20): YYYYMMDDhhmmss right-padded with spaces
    header = (
        f"{xlat:20.5f}{xlon:20.5f}{station_id:<40}{platform_type:<40}"
        f"{platform:<40}{'':<40}{elevation:20.5f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}{-888888:10.0f}"
        f"{'F':<10}{'F':<10}{'F':<10}"
        f"{-888888:10.0f}{-888888:10.0f}{date_char:>20}{slp:13.5f}{0:7.0f}"
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
            station_id = str(row[sid_col]).strip()
            try:
                elevation = float(row[elev_col])
            except Exception:
                elevation = -888888
            if station_id != "":
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
    
    failures = 0
    with open(output_file, "w") as file:
        for idx, data in enumerate(data_list, start=1):
            station_id = str(_get_first(data, ['station_id', 'sid', 'station', 'id'], 'unknown')).strip()
            elevation = elevation_data.get(station_id, -888888)
            try:
                little_r_data = convert_to_little_r(data, elevation)
                file.write(little_r_data)
            except Exception as e:
                failures += 1
                print(f"Skipping row {idx} (station_id={station_id!r}): {e}")

    if failures:
        print(f"Done with {failures} skipped row(s) due to validation errors.")

if __name__ == "__main__":
    main()
