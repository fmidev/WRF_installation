#!/usr/bin/env python3
"""
Parse domain.txt file (WRF namelist.wps format) and extract domain configuration parameters
Author: Mikael Hasu
Date: December 2025
"""

import sys
import re
from pathlib import Path

def parse_namelist_wps(namelist_path):
    """
    Parse a domain.txt file (namelist.wps format) and extract key parameters.
    
    Args:
        namelist_path: Path to the domain.txt file
        
    Returns:
        Dictionary containing parsed parameters
    """
    params = {}
    
    try:
        with open(namelist_path, 'r') as f:
            content = f.read()
        
        # Extract parameters using regex patterns
        # Handle both single values and comma-separated lists
        def extract_param(pattern, text, is_list=False):
            match = re.search(pattern, text, re.IGNORECASE)
            if match:
                value = match.group(1).strip()
                # Remove trailing comma if present
                value = value.rstrip(',')
                if is_list:
                    # Split by comma and strip whitespace
                    return [v.strip().strip("'\"") for v in value.split(',') if v.strip()]
                return value.strip("'\"")
            return None
        
        parent_id = extract_param(r'parent_id\s*=\s*([0-9,\s]+)', content, is_list=True)
        params['parent_id'] = parent_id if parent_id else []
        
        parent_grid_ratio = extract_param(r'parent_grid_ratio\s*=\s*([0-9,\s]+)', content, is_list=True)
        params['parent_grid_ratio'] = parent_grid_ratio if parent_grid_ratio else []
        
        i_parent_start = extract_param(r'i_parent_start\s*=\s*([0-9,\s]+)', content, is_list=True)
        params['i_parent_start'] = i_parent_start if i_parent_start else []
        
        j_parent_start = extract_param(r'j_parent_start\s*=\s*([0-9,\s]+)', content, is_list=True)
        params['j_parent_start'] = j_parent_start if j_parent_start else []
        
        e_we = extract_param(r'e_we\s*=\s*([0-9,\s]+)', content, is_list=True)
        params['e_we'] = e_we if e_we else []
        
        e_sn = extract_param(r'e_sn\s*=\s*([0-9,\s]+)', content, is_list=True)
        params['e_sn'] = e_sn if e_sn else []
        
        params['dx'] = extract_param(r'dx\s*=\s*([0-9.]+)', content)
        params['dy'] = extract_param(r'dy\s*=\s*([0-9.]+)', content)
        params['map_proj'] = extract_param(r"map_proj\s*=\s*'([^']+)'", content)
        params['ref_lat'] = extract_param(r'ref_lat\s*=\s*([0-9.\-]+)', content)
        params['ref_lon'] = extract_param(r'ref_lon\s*=\s*([0-9.\-]+)', content)
        params['truelat1'] = extract_param(r'truelat1\s*=\s*([0-9.\-]+)', content)
        params['truelat2'] = extract_param(r'truelat2\s*=\s*([0-9.\-]+)', content)
        params['stand_lon'] = extract_param(r'stand_lon\s*=\s*([0-9.\-]+)', content)
        params['pole_lat'] = extract_param(r'pole_lat\s*=\s*([0-9.\-]+)', content)
        params['pole_lon'] = extract_param(r'pole_lon\s*=\s*([0-9.\-]+)', content)
        
        return params
        
    except FileNotFoundError:
        print(f"Error: File {namelist_path} not found", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error parsing domain.txt: {e}", file=sys.stderr)
        sys.exit(1)

def format_for_bash(params, domain_index=None):
    """
    Format parameters for bash script consumption.
    If domain_index is specified, extract values for that domain.
    
    Args:
        params: Dictionary of parsed parameters
        domain_index: Index of domain (0-based) to extract, or None for all
        
    Returns:
        String with bash variable assignments
    """
    output = []
    
    for key, value in params.items():
        # Skip None values
        if value is None:
            continue
            
        # Handle list parameters
        if isinstance(value, list):
            if domain_index is not None and domain_index < len(value):
                # Extract single value for specified domain
                output.append(f"{key.upper()}={value[domain_index]}")
            else:
                # Keep as array for bash
                array_str = " ".join(str(v) for v in value)
                output.append(f"{key.upper()}=({array_str})")
        else:
            output.append(f"{key.upper()}={value}")
    
    return "\n".join(output)

def main():
    if len(sys.argv) < 2:
        print("Usage: parse_namelist_wps.py <domain.txt> [domain_index]")
        print("  domain_index: Optional 0-based index for extracting single domain parameters")
        sys.exit(1)
    
    namelist_path = sys.argv[1]
    domain_index = int(sys.argv[2]) if len(sys.argv) > 2 else None
    
    params = parse_namelist_wps(namelist_path)
    print(format_for_bash(params, domain_index))

if __name__ == "__main__":
    main()
