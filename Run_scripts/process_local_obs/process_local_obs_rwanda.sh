#!/bin/bash

# process_local_obs_rwanda.sh
#
# Usage:
#   process_local_obs_rwanda.sh [input_dir] [stationlist.csv] [output.csv]
#
# Default: current directory, stationlist.csv, combined_obs.csv

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
	"$AWK_CMD" -F',' -v OFS=',' -v valid_dttm="$valid_dttm" -v DATE="${YEAR}-${MONTH}-${DAY}" -v unmatched_file="$UNMATCHED_FILE" -v tscol="$TS_COL" -f - "$STATION_FILE" "$FILE_PATH" >> "$OUT_FILE" <<'AWK'
	# helper: convert empty or missing numeric markers (like -9999) to empty fields
	function empty_if_missing(x) { if (x == "" || x+0 < -9000) return ""; return x }
	function is_missing(x) { return (x == "" || x+0 < -9000) }

	NR==FNR {
	    # read stationlist: remove quotes from fields if present
	    for (i=1;i<=NF;i++) gsub(/"/, "", $i)
	    # skip header line if present
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
	    # raw input fields (may be empty)
		ts = $(tscol)
	    T = $3
	    RH = $4
	    WS = $5
	    Wdir = $6
	    P = $7
	    Pcp = $8

	    # Only keep observations that are exactly on the hour
	    minute = ""
	    second = ""
	    if (ts ~ /:/) {
	        # formats like "YYYY-MM-DD HH:MM:SS", "HH:MM:SS" or "HH:MM"
	        n = split(ts, parts, /[ T]/)
	        timepart = parts[n]
	        m = split(timepart, tparts, ":")
	        if (m >= 2) {
	            minute = tparts[2]
	            if (m >= 3) second = tparts[3]
	            else second = "00"
	        }
	    } else if (ts ~ /^[0-9]+$/) {
	        len = length(ts)
	        if (len >= 14) {
	            # YYYYMMDDHHMMSS
	            minute = substr(ts, len-3, 2)
	            second = substr(ts, len-1, 2)
	        } else if (len == 12) {
	            # YYYYMMDDHHMM
	            minute = substr(ts, len-1, 2)
	            second = "00"
	        } else if (len == 10) {
	            # YYYYMMDDHH (no minutes)
	            minute = "00"
	            second = "00"
	        } else if (len == 6) {
	            # HHMMSS
	            minute = substr(ts, len-3, 2)
	            second = substr(ts, len-1, 2)
	        }
	    }

		# If couldn't determine minute, skip the row to be safe
		if (minute == "") next
		# Only accept minute == "00" and second == "" or "00"
		if (!(minute == "00" && (second == "" || second == "00"))) next

		# Normalize original timestamp (ts) into YYYY-MM-DD HH:MM:SS for output
		out_ts = ""
		if (ts ~ /:/) {
			n = split(ts, parts, /[ T]/)
			if (n >= 2) datepart = parts[1]
			else datepart = DATE
			timepart = parts[n]
			m = split(timepart, tparts, ":")
			if (m == 2) timepart = tparts[1] ":" tparts[2] ":00"
			else if (m >= 3) timepart = tparts[1] ":" tparts[2] ":" tparts[3]
			out_ts = datepart " " timepart
		} else if (ts ~ /^[0-9]+$/) {
			len = length(ts)
			if (len >= 14) {
				yyyy = substr(ts,1,4); mm = substr(ts,5,2); dd = substr(ts,7,2)
				hh = substr(ts,9,2); minu = substr(ts,11,2); sec = substr(ts,13,2)
				out_ts = yyyy "-" mm "-" dd " " hh ":" minu ":" sec
			} else if (len == 12) {
				yyyy = substr(ts,1,4); mm = substr(ts,5,2); dd = substr(ts,7,2)
				hh = substr(ts,9,2); minu = substr(ts,11,2)
				out_ts = yyyy "-" mm "-" dd " " hh ":" minu ":00"
			} else if (len == 10) {
				yyyy = substr(ts,1,4); mm = substr(ts,5,2); dd = substr(ts,7,2)
				hh = substr(ts,9,2)
				out_ts = yyyy "-" mm "-" dd " " hh ":00:00"
			} else if (len == 6) {
				hh = substr(ts,1,2); minu = substr(ts,3,2); sec = substr(ts,5,2)
				out_ts = DATE " " hh ":" minu ":" sec
			} else {
				out_ts = DATE " " ts
			}
		} else {
			out_ts = DATE " " ts
		}

	    # output Td2m and Q2m are left empty
	    Td_out = ""
	    Q_out = ""

	    latv = (sid in lat ? lat[sid] : "")
	    lonv = (sid in lon ? lon[sid] : "")
	    elevv = (sid in elev ? elev[sid] : "")
	    # if coordinates missing, record unmatched sid
	    if (latv == "" && lonv == "" && elevv == "") {
		# append SID once per occurrence; we'll dedupe later and skip printing
		print sid >> unmatched_file
	    }
	    else {
		T_out = empty_if_missing(T)
		RH_out = empty_if_missing(RH)
		P_out = empty_if_missing(P)
		Pcp_out = empty_if_missing(Pcp)
		Wdir_out = empty_if_missing(Wdir)
		WS_out = empty_if_missing(WS)

	print out_ts, sid, latv, lonv, elevv, T_out, Td_out, RH_out, Q_out, P_out, Pcp_out, Wdir_out, WS_out
			}
	}
AWK

}

# main
if [ "$#" -lt 4 ]; then usage; fi

YEAR=$1
MONTH=$(printf "%02d" "$2")
DAY=$(printf "%02d" "$3")
HOUR=$(printf "%02d" "$4")

INPUT_DIR="${5:-.}"
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
