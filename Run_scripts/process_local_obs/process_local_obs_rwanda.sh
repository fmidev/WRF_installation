#!/bin/bash

# process_local_obs_rwanda.sh
#
# Usage:
#   process_local_obs_rwanda.sh YYYY MM DD HH [input_dir] [stationlist.csv] [output.csv]
#

die() { echo "$*" >&2; exit 1; }

usage() {
	echo "Usage: $0 YYYY MM DD HH [input_dir] [stationlist.csv] [output.csv] [ts_col]" >&2
	exit 2
}

detect_awk() {
	if command -v gawk >/dev/null 2>&1; then
		echo gawk
	elif command -v awk >/dev/null 2>&1; then
		echo awk
	else
		die "No awk found (gawk preferred). Install gawk or ensure awk is available."
	fi
}

prepare_output() {
	outdir=$(dirname -- "$OUT_FILE")
	mkdir -p "$outdir"
	printf '%s\n' "valid_dttm,SID,lat,lon,elev,T2m,Td2m,RH2m,Q2m,Pressure,Pcp,Wdir,WS" > "$OUT_FILE"
	rm -f "$UNMATCHED_FILE"
}

run_awk() {
	"$AWK_CMD" -F',' -v OFS=',' -v valid_dttm="$valid_dttm" -v DATE="${YEAR}-${MONTH}-${DAY}" \
	           -v unmatched_file="$UNMATCHED_FILE" -v tscol="$TS_COL" \
	           -f - "$STATION_FILE" "$FILE_PATH" >> "$OUT_FILE" <<'AWK'
	function empty_if_missing(x) { if (x == "" || x+0 < -9000) return ""; return x }

	NR==FNR {
	    for (i=1;i<=NF;i++) gsub(/"/, "", $i)
	    if (FNR==1) next
	    sid = $1+0
	    lat[sid] = $2
	    lon[sid] = $3
	    elev[sid] = $4
	    next
	}

	{
	    sid = $1+0
	    if (sid == 0) next
	    ts = $(tscol)
	    T = $3; RH = $4; WS = $5; Wdir = $6; P = $7; Pcp = $8

	    gsub(/T/, " ", ts)
	    split(ts, dt_parts, /[ :T-]/)
	    yyyy = dt_parts[1]; mm = dt_parts[2]; dd = dt_parts[3]
	    hh = dt_parts[4];  minu = dt_parts[5]
	    if (yyyy == "" || hh == "") next

	    hour = hh + 0; minute = minu + 0

	    # accumulation ends at this top of hour
	    end_hour = hour
	    out_ts = sprintf("%s-%s-%s %02d:00:00", yyyy, mm, dd, end_hour)
	    accum_key = out_ts

	    pcp_sum[sid, accum_key] += (Pcp == "" || Pcp+0 < -9000 ? 0 : Pcp+0)
	    T_last[sid, accum_key] = T
	    RH_last[sid, accum_key] = RH
	    WS_last[sid, accum_key] = WS
	    Wdir_last[sid, accum_key] = Wdir
	    P_last[sid, accum_key] = P
	}

	END {
	    PROCINFO["sorted_in"] = "@ind_str_asc"
	    for (key in pcp_sum) {
	        split(key, k, SUBSEP)
	        sid = k[1]
	        hourkey = k[2]

	        latv = (sid in lat ? lat[sid] : "")
	        lonv = (sid in lon ? lon[sid] : "")
	        elevv = (sid in elev ? elev[sid] : "")
	        if (latv == "" && lonv == "" && elevv == "") {
	            unmatched[sid] = 1
	            continue
	        }

	        print hourkey, sid, latv, lonv, elevv, \
	              empty_if_missing(T_last[sid, hourkey]), "", \
	              empty_if_missing(RH_last[sid, hourkey]), "", \
	              empty_if_missing(P_last[sid, hourkey]), \
	              empty_if_missing(pcp_sum[sid, hourkey]), \
	              empty_if_missing(Wdir_last[sid, hourkey]), \
	              empty_if_missing(WS_last[sid, hourkey])
	    }

	    for (s in unmatched) print s >> unmatched_file
	}
AWK
}


# main
if [ "$#" -lt 4 ]; then usage; fi

YEAR=$1
MONTH=$(printf "%02d" "$2")
DAY=$(printf "%02d" "$3")
HOUR=$(printf "%02d" "$4")

INPUT_DIR="${5:-/home/wrf/Verification/OBS/}"
# default stationlist and output directory per request
STATION_FILE="${6:-/home/wrf/Verification/Data/Static/stationlist.csv}"
OUT_FILE="${7:-/home/wrf/Verification/Data/Obs/verif_obs_${YEAR}${MONTH}${DAY}${HOUR}00.csv}"
TS_COL="${8:-2}" #timestamp column

# construct timestamps
ts_full="${YEAR}${MONTH}${DAY}${HOUR}00"
valid_dt="${YEAR}${MONTH}${DAY}${HOUR}"
valid_dttm="${YEAR}-${MONTH}-${DAY} ${HOUR}:00:00"

# find file for that hour
FILE_PATH="$INPUT_DIR/${ts_full}_aws_rwanda.csv"
[ -f "$FILE_PATH" ] || die "Input file not found: $FILE_PATH"

AWK_CMD=$(detect_awk)

outdir=$(dirname -- "$OUT_FILE")
UNMATCHED_FILE="$outdir/unmatched_sids_${valid_dt}.txt"

prepare_output
echo "Writing output to: $OUT_FILE"

run_awk

# deduplicate unmatched list
if [ -f "$UNMATCHED_FILE" ]; then
	sort -u -o "$UNMATCHED_FILE" "$UNMATCHED_FILE"
	echo "Unmatched SIDs written to: $UNMATCHED_FILE"
fi

echo "Done. Output: $OUT_FILE"
