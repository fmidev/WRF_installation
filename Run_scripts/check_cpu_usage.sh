#!/bin/bash

# WRF CPU Decomposition Calculator
# Reads domain configuration from domain.txt and suggests optimal CPU decomposition

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOMAIN_FILE="${SCRIPT_DIR}/domain.txt"
VERBOSE=0
QUIET=0
MAX_CPU=""

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

usage() {
    cat << EOF
WRF CPU Decomposition Calculator

Usage: $0 [-c <cpus>] [-f <file>] [-v] [-q] [-h]

Options:
  -c      Max CPUs available (required)
  -f      Domain config file (default: domain.txt in script directory)
  -v      Verbose mode
  -q      Quiet mode (only output: nproc_x nproc_y efficiency)
  -h      Show help

Domain file format (domain.txt):
  max_dom = 2
  parent_grid_ratio = 1, 3
  i_parent_start = 1, 50
  j_parent_start = 1, 60
  e_we = 270, 295
  e_sn = 290, 346

Example: $0 -c 59
EOF
    exit 1
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -c)
            MAX_CPU="$2"
            shift 2
            ;;
        -f)
            DOMAIN_FILE="$2"
            shift 2
            ;;
        -v)
            VERBOSE=1
            shift
            ;;
        -q)
            QUIET=1
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Validate inputs
if [[ -z "$MAX_CPU" ]]; then
    echo -e "${RED}ERROR: Max CPUs (-c) is required${NC}"
    usage
fi

if ! [[ "$MAX_CPU" =~ ^[0-9]+$ ]]; then
    echo -e "${RED}ERROR: Max CPUs must be a positive integer${NC}"
    exit 1
fi

if [[ ! -f "$DOMAIN_FILE" ]]; then
    echo -e "${RED}ERROR: Domain file not found: $DOMAIN_FILE${NC}"
    echo "Create a domain.txt file with WRF namelist parameters (see -h for format)"
    exit 1
fi

# Parse domain configuration file
parse_domain_file() {
    local file=$1
    
    # Extract values from namelist format
    local max_dom=$(grep -i "max_dom" "$file" | sed 's/.*=\s*\([0-9]*\).*/\1/')
    local e_we=$(grep -i "e_we" "$file" | sed 's/.*=\s*\(.*\)/\1/' | tr -d ' ')
    local e_sn=$(grep -i "e_sn" "$file" | sed 's/.*=\s*\(.*\)/\1/' | tr -d ' ')
    local parent_grid_ratio=$(grep -i "parent_grid_ratio" "$file" | sed 's/.*=\s*\(.*\)/\1/' | tr -d ' ')
    local i_parent_start=$(grep -i "i_parent_start" "$file" | sed 's/.*=\s*\(.*\)/\1/' | tr -d ' ')
    local j_parent_start=$(grep -i "j_parent_start" "$file" | sed 's/.*=\s*\(.*\)/\1/' | tr -d ' ')
    
    # Convert comma-separated to arrays
    IFS=',' read -ra E_WE_ARR <<< "$e_we"
    IFS=',' read -ra E_SN_ARR <<< "$e_sn"
    IFS=',' read -ra RATIO_ARR <<< "$parent_grid_ratio"
    IFS=',' read -ra ISTART_ARR <<< "$i_parent_start"
    IFS=',' read -ra JSTART_ARR <<< "$j_parent_start"
    
    echo "$max_dom|${E_WE_ARR[@]}|${E_SN_ARR[@]}|${RATIO_ARR[@]}|${ISTART_ARR[@]}|${JSTART_ARR[@]}"
}

# Read and parse domain file
[[ $QUIET -eq 0 ]] && echo "Reading domain configuration from: $DOMAIN_FILE"
[[ $QUIET -eq 0 ]] && echo ""
DOMAIN_CONFIG=$(parse_domain_file "$DOMAIN_FILE")
IFS='|' read -r MAX_DOM E_WE_STR E_SN_STR RATIO_STR ISTART_STR JSTART_STR <<< "$DOMAIN_CONFIG"

read -ra E_WE <<< "$E_WE_STR"
read -ra E_SN <<< "$E_SN_STR"
read -ra PARENT_RATIO <<< "$RATIO_STR"

if [[ -z "$MAX_DOM" || ${#E_WE[@]} -eq 0 ]]; then
    echo -e "${RED}ERROR: Could not parse domain configuration${NC}" >&2
    exit 1
fi

if [[ $QUIET -eq 0 ]]; then
    echo "Configuration found:"
    echo "  max_dom = $MAX_DOM"
    echo "  e_we = ${E_WE[@]}"
    echo "  e_sn = ${E_SN[@]}"
    echo "  parent_grid_ratio = ${PARENT_RATIO[@]}"
    echo ""
fi

# Prime factorization
factorize() {
    local n=$1
    local factors=""
    local d=2
    
    while [[ $((n % d)) -eq 0 ]]; do
        factors="${factors}${d} "
        n=$((n / d))
    done
    
    d=3
    while [[ $((d * d)) -le $n ]]; do
        while [[ $((n % d)) -eq 0 ]]; do
            factors="${factors}${d} "
            n=$((n / d))
        done
        d=$((d + 2))
    done
    
    if [[ $n -gt 1 ]]; then
        factors="${factors}${n}"
    fi
    
    echo "$factors"
}

# Format factorization output
format_factorization() {
    local n=$1
    local factors=$(factorize $n)
    
    if [[ -z "$factors" || "$factors" == "$n" ]]; then
        echo "prime"
        return
    fi
    
    # Count factor occurrences
    declare -A factor_count
    for f in $factors; do
        ((factor_count[$f]++))
    done
    
    # Format
    local result=""
    for f in $(echo "${!factor_count[@]}" | tr ' ' '\n' | sort -n); do
        local count=${factor_count[$f]}
        if [[ $count -eq 1 ]]; then
            result="${result}${f} × "
        else
            result="${result}${f}^${count} × "
        fi
    done
    
    echo "${result% × }"
}

# Main calculation
calculate_nproc() {
    local max_cpu=$1
    shift
    local -a e_we=("$@")
    local num_domains=${#E_WE[@]}
    
    local min_tile=10
    
    [[ $QUIET -eq 0 ]] && echo "Analyzing $num_domains domain(s)..."
    [[ $QUIET -eq 0 ]] && echo ""
    
    # Calculate staggered dimensions for all domains
    local -a stag_x
    local -a stag_y
    for ((i=0; i<num_domains; i++)); do
        stag_x[$i]=$((E_WE[i] - 1))
        stag_y[$i]=$((E_SN[i] - 1))
        if [[ $QUIET -eq 0 ]]; then
            echo "Domain $((i+1)): e_we=${E_WE[i]}, e_sn=${E_SN[i]}"
            echo "  Staggered: ${stag_x[i]} × ${stag_y[i]}"
            echo "  Factorization: (${stag_x[i]})=$(format_factorization ${stag_x[i]}), (${stag_y[i]})=$(format_factorization ${stag_y[i]})"
        fi
    done
    [[ $QUIET -eq 0 ]] && echo ""
    
    # Find common divisors across all domains
    local valid_nx=()
    local max_search_x=0
    for ((i=0; i<num_domains; i++)); do
        [[ ${E_WE[i]} -gt $max_search_x ]] && max_search_x=${E_WE[i]}
    done
    
    for ((nx=1; nx<=max_search_x; nx++)); do
        local valid=1
        for ((i=0; i<num_domains; i++)); do
            if [[ $((stag_x[i] % nx)) -ne 0 ]] || [[ $((E_WE[i]/nx)) -lt $min_tile ]]; then
                valid=0
                break
            fi
        done
        [[ $valid -eq 1 ]] && valid_nx+=($nx)
    done
    
    [[ $QUIET -eq 0 ]] && echo "Valid nproc_x: ${valid_nx[@]}"
    
    local valid_ny=()
    local max_search_y=0
    for ((i=0; i<num_domains; i++)); do
        [[ ${E_SN[i]} -gt $max_search_y ]] && max_search_y=${E_SN[i]}
    done
    
    for ((ny=1; ny<=max_search_y; ny++)); do
        local valid=1
        for ((i=0; i<num_domains; i++)); do
            if [[ $((stag_y[i] % ny)) -ne 0 ]] || [[ $((E_SN[i]/ny)) -lt $min_tile ]]; then
                valid=0
                break
            fi
        done
        [[ $valid -eq 1 ]] && valid_ny+=($ny)
    done
    
    [[ $QUIET -eq 0 ]] && echo "Valid nproc_y: ${valid_ny[@]}"
    [[ $QUIET -eq 0 ]] && echo ""
    
    local best_nx=1 best_ny=1 best_cpus=1
    
    if [[ $VERBOSE -eq 1 ]]; then
        echo "Testing all valid combinations:"
        echo "======================================================="
        printf "  %2s × %2s = %3s CPUs  " "X" "Y" "Tot"
        for ((i=0; i<num_domains; i++)); do
            printf "| D%02d tiles " $((i+1))
        done
        echo ""
        echo "-------------------------------------------------------"
    fi
    
    # Find best combination
    for nx in "${valid_nx[@]}"; do
        for ny in "${valid_ny[@]}"; do
            local total=$((nx * ny))
            [[ $total -gt $max_cpu ]] && continue
            
            if [[ $VERBOSE -eq 1 ]]; then
                printf "  %2d × %2d = %3d CPUs  " $nx $ny $total
                for ((i=0; i<num_domains; i++)); do
                    local tile_x=$((E_WE[i] / nx))
                    local tile_y=$((E_SN[i] / ny))
                    printf "| %3d×%-3d    " $tile_x $tile_y
                done
                echo ""
            fi
            
            if [[ $total -gt $best_cpus ]]; then
                best_cpus=$total
                best_nx=$nx
                best_ny=$ny
            elif [[ $total -eq $best_cpus ]]; then
                local current_balance=$(echo "scale=4; if ($nx > $ny) $nx/$ny else $ny/$nx" | bc)
                local best_balance=$(echo "scale=4; if ($best_nx > $best_ny) $best_nx/$best_ny else $best_ny/$best_nx" | bc)
                
                if [[ $(echo "$current_balance < $best_balance" | bc) -eq 1 ]]; then
                    best_nx=$nx
                    best_ny=$ny
                fi
            fi
        done
    done
    
    if [[ $VERBOSE -eq 1 ]]; then
        echo ""
    fi
    
    local efficiency=$(echo "scale=1; $best_cpus * 100 / $max_cpu" | bc)
    
    # Quiet mode: only output nproc_x nproc_y efficiency
    if [[ $QUIET -eq 1 ]]; then
        echo "$best_nx $best_ny $efficiency"
        return
    fi
    
    echo "======================================="
    echo -e "${GREEN}OPTIMAL DECOMPOSITION${NC}"
    echo "======================================="
    echo "  nproc_x: $best_nx"
    echo "  nproc_y: $best_ny"
    echo -e "  ${GREEN}Total CPUs: ${best_cpus}${NC} / $max_cpu available"
    
    if (( $(echo "$efficiency < 50" | bc -l) )); then
        echo -e "  ${RED}Efficiency: ${efficiency}% (LOW)${NC}"
    elif (( $(echo "$efficiency < 80" | bc -l) )); then
        echo -e "  ${YELLOW}Efficiency: ${efficiency}%${NC}"
    else
        echo -e "  ${GREEN}Efficiency: ${efficiency}%${NC}"
    fi
    echo ""
    
    echo "Tile sizes per CPU:"
    for ((i=0; i<num_domains; i++)); do
        local tile_x=$((E_WE[i] / best_nx))
        local tile_y=$((E_SN[i] / best_ny))
        echo "  Domain $((i+1)): ${tile_x} × ${tile_y} grid points"
    done
    
    # Suggest better configs if efficiency is low
    if (( $(echo "$efficiency < 90" | bc -l) )); then
        echo ""
        echo "======================================="
        echo -e "${YELLOW}DOMAIN SIZE SUGGESTIONS${NC}"
        echo "======================================="
        suggest_better_domains $max_cpu $efficiency
    fi
    echo "======================================="
}

# Suggest better domain configurations
suggest_better_domains() {
    local max_cpu=$1
    local current_eff=$2
    local target_efficiency=90
    local min_tile=10
    local search_range=50
    
    local num_domains=${#E_WE[@]}
    
    echo "Target: ≥${target_efficiency}% efficiency ($max_cpu CPUs)"
    echo "Current: ${current_eff}% efficiency"
    echo ""
    
    # Good e_we/e_sn values where (value-1) has many divisors
    local good_values=(121 145 169 181 193 217 241 253 265 289 301 313 325 337 349 361 373 385 397 409 421 433 457 481 505 513 529 541 577 601 625)
    
    # Check if configuration is valid for WRF nesting
    check_nesting_validity() {
        local -a test_e_we=("$@")
        local num_d=$((${#test_e_we[@]} / 2))
        
        # For nested domains, check parent_grid_ratio constraints
        for ((d=1; d<num_d; d++)); do
            local parent_d=$((d - 1))
            local ratio=${PARENT_RATIO[d]}
            [[ -z "$ratio" ]] && ratio=3
            
            local child_x=${test_e_we[d]}
            local child_y=${test_e_we[d + num_d]}
            
            # Child domain staggered dimensions must be divisible by parent_grid_ratio
            local child_stag_x=$((child_x - 1))
            local child_stag_y=$((child_y - 1))
            
            if [[ $((child_stag_x % ratio)) -ne 0 ]] || [[ $((child_stag_y % ratio)) -ne 0 ]]; then
                return 1
            fi
        done
        return 0
    }
    
    # Check configuration and return CPU count
    check_config() {
        local -a test_e_we=("$@")
        local num_d=$((${#test_e_we[@]} / 2))
        
        # Extract x and y dimensions
        local -a x_dims
        local -a y_dims
        for ((i=0; i<num_d; i++)); do
            x_dims[$i]=${test_e_we[i]}
            y_dims[$i]=${test_e_we[i + num_d]}
        done
        
        # Check nesting validity
        check_nesting_validity "${test_e_we[@]}"
        [[ $? -ne 0 ]] && echo "0" && return
        
        # Find valid decompositions
        local valid_nx=()
        for ((nx=1; nx<=500; nx++)); do
            local valid=1
            for ((i=0; i<num_d; i++)); do
                local stag_x=$((x_dims[i] - 1))
                if [[ $((stag_x % nx)) -ne 0 ]] || [[ $((x_dims[i]/nx)) -lt $min_tile ]]; then
                    valid=0
                    break
                fi
            done
            [[ $valid -eq 1 ]] && valid_nx+=($nx)
        done
        
        local valid_ny=()
        for ((ny=1; ny<=500; ny++)); do
            local valid=1
            for ((i=0; i<num_d; i++)); do
                local stag_y=$((y_dims[i] - 1))
                if [[ $((stag_y % ny)) -ne 0 ]] || [[ $((y_dims[i]/ny)) -lt $min_tile ]]; then
                    valid=0
                    break
                fi
            done
            [[ $valid -eq 1 ]] && valid_ny+=($ny)
        done
        
        # Find best CPU count
        local best_cpus=1
        for nx in "${valid_nx[@]}"; do
            for ny in "${valid_ny[@]}"; do
                local total=$((nx * ny))
                [[ $total -gt $max_cpu ]] && continue
                [[ $total -gt $best_cpus ]] && best_cpus=$total
            done
        done
        
        echo "$best_cpus"
    }
    
    # For nested domains, suggest configurations that respect parent_grid_ratio
    if [[ $num_domains -eq 2 ]]; then
        echo "Searching for better 2-domain configurations..."
        echo ""
        
        local ratio=${PARENT_RATIO[1]}
        [[ -z "$ratio" ]] && ratio=3
        
        local -a suggestions
        
        # Try combinations
        for val1_x in "${good_values[@]}"; do
            local diff_x=$((val1_x - E_WE[0]))
            [[ ${diff_x#-} -gt $search_range ]] && continue
            
            for val1_y in "${good_values[@]}"; do
                local diff_y=$((val1_y - E_SN[0]))
                [[ ${diff_y#-} -gt $search_range ]] && continue
                
                # For nested domain, try multiples that respect parent_grid_ratio
                for val2_x in "${good_values[@]}"; do
                    local diff2_x=$((val2_x - E_WE[1]))
                    [[ ${diff2_x#-} -gt $search_range ]] && continue
                    
                    # Check if child staggered dimension is divisible by ratio
                    local child_stag_x=$((val2_x - 1))
                    [[ $((child_stag_x % ratio)) -ne 0 ]] && continue
                    
                    for val2_y in "${good_values[@]}"; do
                        local diff2_y=$((val2_y - E_SN[1]))
                        [[ ${diff2_y#-} -gt $search_range ]] && continue
                        
                        local child_stag_y=$((val2_y - 1))
                        [[ $((child_stag_y % ratio)) -ne 0 ]] && continue
                        
                        # Check configuration
                        local cpus=$(check_config $val1_x $val2_x $val1_y $val2_y)
                        [[ $cpus -eq 0 ]] && continue
                        
                        local eff=$(echo "scale=1; $cpus * 100 / $max_cpu" | bc)
                        
                        if (( $(echo "$eff >= $target_efficiency" | bc -l) )); then
                            local diff_x1=$((val1_x - E_WE[0]))
                            local diff_y1=$((val1_y - E_SN[0]))
                            local diff_x2=$((val2_x - E_WE[1]))
                            local diff_y2=$((val2_y - E_SN[1]))
                            local total_diff=$((${diff_x1#-} + ${diff_y1#-} + ${diff_x2#-} + ${diff_y2#-}))
                            
                            suggestions+=("$eff|$total_diff|$val1_x|$val1_y|$val2_x|$val2_y|$cpus")
                        fi
                    done
                done
            done
        done
        
        # Display suggestions
        if [[ ${#suggestions[@]} -gt 0 ]]; then
            echo "Found ${#suggestions[@]} valid configurations with ≥${target_efficiency}% efficiency"
            echo ""
            echo "Top 5 Recommendations:"
            echo "================================================================"
            
            IFS=$'\n' sorted=($(sort -t'|' -k1,1nr -k2,2n <<< "${suggestions[*]}"))
            unset IFS
            
            local count=0
            for suggestion in "${sorted[@]}"; do
                [[ $count -ge 5 ]] && break
                
                IFS='|' read -r eff total_diff d1x d1y d2x d2y cpus <<< "$suggestion"
                
                count=$((count + 1))
                echo -e "${GREEN}Option $count: ${eff}% efficiency ($cpus CPUs)${NC}"
                echo "  Domain 1: e_we=$d1x, e_sn=$d1y  (Δ: $((d1x - E_WE[0])), $((d1y - E_SN[0])))"
                echo "  Domain 2: e_we=$d2x, e_sn=$d2y  (Δ: $((d2x - E_WE[1])), $((d2y - E_SN[1])))"
                
                if [[ $count -eq 1 ]]; then
                    local stag_x1=$((d1x - 1))
                    local stag_y1=$((d1y - 1))
                    local stag_x2=$((d2x - 1))
                    local stag_y2=$((d2y - 1))
                    echo "  Factorizations:"
                    echo "    D1: ($stag_x1)=$(format_factorization $stag_x1), ($stag_y1)=$(format_factorization $stag_y1)"
                    echo "    D2: ($stag_x2)=$(format_factorization $stag_x2), ($stag_y2)=$(format_factorization $stag_y2)"
                    echo "  Nesting valid: (${stag_x2} mod $ratio)=0, (${stag_y2} mod $ratio)=0 ✓"
                fi
                echo ""
            done
        else
            echo "No valid configurations found with ≥${target_efficiency}% efficiency"
            echo ""
            echo "Tips:"
            echo "  - Choose e_we/e_sn where (value-1) has many factors"
            echo "  - For nested domains, (e_we-1) and (e_sn-1) must be divisible by parent_grid_ratio ($ratio)"
            echo "  - Good values: 121, 145, 181, 241, 289, 361, 433, 481"
        fi
    else
        echo "Suggestions for $num_domains domains not yet implemented"
        echo "Tips:"
        echo "  - Choose e_we/e_sn where (value-1) has many factors"
        echo "  - Ensure all domains share common divisors"
    fi
}

# Run calculation
calculate_nproc $MAX_CPU
