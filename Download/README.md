# Running WRF with ECMWF Boundary Conditions

ECMWF open data is published in **GRIB2 format**. The download script retrieves these GRIB2 files directly from `https://data.ecmwf.int/forecasts/`, converts them to a WPS-compatible packing format, and relabels soil level metadata so that WPS `ungrib` can decode them correctly.

## Prerequisites

- WPS 4.6.0 and WRF 4.7.1 compiled and installed
- `curl` or `wget` — for downloading GRIB2 files from ECMWF
- `wgrib2` — for repacking GRIB2 files to simple packing and relabelling soil level strings

---

## 1. Patch WPS for ECMWF Compatibility

Stock WPS does not support ECMWF GRIB2 soil layers (level type 151) or the correct SKINTEMP GRIB2 encoding. Two changes are required before running WPS with ECMWF data. **Apply these patches once before first use of WPS with ECMWF data.**

### a) Patch `ungrib/src/rd_grib2.F`

Open `$BASE/WPS/ungrib/src/rd_grib2.F` and add the following two code blocks.

**Block 1:** After the line containing `!MGD ... my_field is now ... my_field`, insert a new section that handles level type 151 (depth below land surface):

```fortran
! Level type 151 - depth below land surface (ECMWF soil layers)
              if ( gfld%ipdtmpl(10) .eq. 151 ) then
                glevel1 = gfld%ipdtmpl(12)*
     &                    (10.**(-1.*gfld%ipdtmpl(11)))
                glevel2 = gfld%ipdtmpl(15)*
     &                    (10.**(-1.*gfld%ipdtmpl(14)))
                TMP9LOOP: do j = 1, maxvar
                  if ((g2code(4,j) .eq. 151) .and.
     &               (gfld%ipdtmpl(2) .eq. g2code(3,j)) .and.
     &               (glevel1 .eq. level1(j)) .and.
     &               ((glevel2 .eq. level2(j)) .or.
     &                                   (level2(j) .le. -88))) then
                    my_field = namvar(j)
                    exit TMP9LOOP
                  endif
                enddo TMP9LOOP
                if (j .gt. maxvar ) then
                  write(6,'(a,i6,a,i6,a)') 'Soil level ',
     &               gfld%ipdtmpl(12), '-', gfld%ipdtmpl(15),
     &           ' in the GRIB2 file, was not found in the Vtable'
                  cycle MATCH_LOOP
                endif
              endif
```

**Block 2:** In the level-value assignment section near the line `level=200100.` (misc near ground/surface levels), add an `elseif` branch for level type 151:

```fortran
              elseif(gfld%ipdtmpl(10).eq.151) then
                 ! Depth below land surface (ECMWF soil layers)
                 glevel1 = gfld%ipdtmpl(12) *
     &                    (10.**(-1.*gfld%ipdtmpl(11)))
                 glevel2 = gfld%ipdtmpl(15) *
     &                    (10.**(-1.*gfld%ipdtmpl(14)))
                 ! Use standard surface level for METGRID.TBL compatibility
                 level = 200100.
```

After editing, recompile WPS:

```bash
cd $BASE/WPS
./compile
```

### b) Update `ungrib/Variable_Tables/Vtable.ECMWF`

Open `$BASE/WPS/ungrib/Variable_Tables/Vtable.ECMWF` and make the following changes.

**Fix the SKINTEMP line** — replace the existing SKINTEMP entry with the corrected GRIB2 parameters:

```
 235 |  1   |   0  |      | SKINTEMP | K        | Skin Temperature                          |  0  |  0  | 17  |  1  |
```

**Add soil layer entries** before the final separator line. These define all 4 soil temperature and 4 soil moisture layers using level type 151:

```
 139 | 151  |   0  |   1  | ST000007 | K        | Soil temp layer 0 (ECMWF 0-7cm)           |   2 |   3 |  18 | 151 |
 170 | 151  |   1  |   2  | ST007028 | K        | Soil temp layer 1 (ECMWF 7-28cm)          |   2 |   3 |  18 | 151 |
 183 | 151  |   2  |   3  | ST028100 | K        | Soil temp layer 2 (ECMWF 28-100cm)        |   2 |   3 |  18 | 151 |
 236 | 151  |   3  |   4  | ST100289 | K        | Soil temp layer 3 (ECMWF 100-289cm)       |   2 |   3 |  18 | 151 |
  39 | 151  |   0  |   1  | SM000007 | m3 m-3   | Soil moisture layer 0 (ECMWF 0-7cm)       |   2 |   0 |  25 | 151 |
  40 | 151  |   1  |   2  | SM007028 | m3 m-3   | Soil moisture layer 1 (ECMWF 7-28cm)      |   2 |   0 |  25 | 151 |
  41 | 151  |   2  |   3  | SM028100 | m3 m-3   | Soil moisture layer 2 (ECMWF 28-100cm)    |   2 |   0 |  25 | 151 |
  42 | 151  |   3  |   4  | SM100289 | m3 m-3   | Soil moisture layer 3 (ECMWF 100-289cm)   |   2 |   0 |  25 | 151 |
```

No recompilation is needed after editing the Vtable.

---

## 2. Configure `ecmwf.cnf`

Place `ecmwf.cnf` at `$BASE/scripts/ecmwf.cnf` (default `$BASE` = `/home/wrf/WRF_Model`):

| Parameter | Default | Description |
|---|---|---|
| `MODEL_PRODUCER` | `ifs` | ECMWF model |
| `MODEL_VERSION` | `0p25` | Resolution: `0p25` (0.25°) or `0p4` (0.4°) |
| `MAX_FORECAST_HOUR` | `72` | Forecast length in hours (up to 144 h) |
| `VALID_HOURS` | `00\|06\|12\|18` | UTC cycles to download |
| `WRF_COPY_DEST` | `/home/wrf/WRF_Model/ECMWF/` | Final destination for WPS input |

---

## 3. Download ECMWF GRIB2 Data

The script downloads GRIB2 forecast files from the ECMWF open data server and prepares them for WPS.

```bash
cd /home/wrf/WRF_installation/Download
bash get_ecmwf.sh
```

### What the script does

#### Configuration loading
The script first loads `/home/wrf/WRF_Model/scripts/ecmwf.cnf` if it exists, then applies built-in defaults for any unset parameters. Command-line flags override both. Built-in defaults are:

| Parameter | Built-in default |
|---|---|
| `MODEL_PRODUCER` | `ifs` |
| `MODEL_VERSION` | `0p25` |
| `VALID_HOURS` | `00\|06\|12\|18` |
| `MAX_FORECAST_HOUR` | `12` |

> **Note:** The built-in default for `MAX_FORECAST_HOUR` is only 12 hours. Set `MAX_FORECAST_HOUR=72` (or higher) in `ecmwf.cnf` for a useful forecast length.

#### Log file management
When run non-interactively (e.g. from cron, where `$TERM=dumb`), all output is redirected to `/home/wrf/WRF_Model/logs/ecmwf_<HH>.log`. Log files from previous days are automatically deleted at the start of each run.

#### Finding the latest available forecast
The script probes the ECMWF open data server using HTTP HEAD requests to find the most recently published forecast. It checks today's and yesterday's dates, cycling through 18z → 12z → 06z → 00z and stopping at the first cycle that has its 0-hour file available. The model type is set automatically based on cycle time:

| Cycle | Model type | Description |
|---|---|---|
| 00z, 12z | `oper` | Main high-resolution operational forecast |
| 06z, 18z | `scda` | Short cut-off data assimilation forecast |

#### Skipping already-processed data
If the directory `$BASE/ECMWF/<YYYYMMDDHH>/` already contains a `.converted` marker file and GRIB2 files, the script exits immediately without re-downloading. If the marker file exists but GRIB2 files are missing, it removes the marker and re-downloads.

#### Skipping invalid cycles
If the discovered forecast cycle is not listed in `VALID_HOURS`, the script exits cleanly without downloading anything. Use this to limit downloads to, e.g., only 00z and 12z.

#### Downloading GRIB2 files
ECMWF publishes one GRIB2 file per forecast step. Files are downloaded from:
```
https://data.ecmwf.int/forecasts/<YYYYMMDD>/<HH>z/ifs/<VERSION>/<TYPE>/
```
One GRIB2 file per forecast step, every 3 hours from 0 to `MAX_FORECAST_HOUR`. Each GRIB2 file contains all atmospheric and surface fields for that forecast step. Filenames follow the pattern:
```
<YYYYMMDDHH>0000-<F>h-<TYPE>-fc.grib2
```
Both `curl` and `wget` are supported (curl is preferred). Each GRIB2 file download is retried up to 3 times with a 5-second delay on failure. Failed files are removed.

#### GRIB2 format conversion

ECMWF distributes data using CCSDS, JPEG, or complex packing, which WPS `ungrib` cannot read. The script performs the following `wgrib2` operations on every downloaded file. The same commands can be run manually if needed.

**Step 1 — Check the packing type of a file**

```bash
wgrib2 -d 1 -packing <file>.grib2
```

Look for `packing=grid_ccsds`, `packing=jpeg`, or `packing=complex` in the output. If the output shows `packing=simple`, no conversion is needed for that file.

**Step 2 — Repack to simple packing**

```bash
wgrib2 <file>.grib2 -set_grib_type simple -grib_out res1.grb2
```

Converts one GRIB2 file from CCSDS/JPEG/complex packing to simple packing and writes the result to `res1.grb2`. The original file is not modified yet.

**Step 3 — Relabel soil level strings**

```bash
wgrib2 res1.grb2 \
    -if ":soil level 0 - soil level 1" -set_lev "0-0.07 m below ground" \
    -elseif ":soil level 1 - soil level 2" -set_lev "0.07-0.28 m below ground" \
    -elseif ":soil level 2 - soil level 3" -set_lev "0.28-1 m below ground" \
    -elseif ":soil level 3 - soil level 4" -set_lev "1-2.89 m below ground" \
    -endif -grib res.grb2
```

Replaces ECMWF's generic soil layer names with the depth-in-metres strings that WPS `ungrib` expects:

| ECMWF label | WRF label |
|---|---|
| `soil level 0 - soil level 1` | `0-0.07 m below ground` |
| `soil level 1 - soil level 2` | `0.07-0.28 m below ground` |
| `soil level 2 - soil level 3` | `0.28-1 m below ground` |
| `soil level 3 - soil level 4` | `1-2.89 m below ground` |

All other fields pass through unchanged. Output is written to `res.grb2`.

**Step 4 — Replace the original file**

```bash
mv res.grb2 <file>.grib2
rm -f res1.grb2
```

The original downloaded file is overwritten with the converted and relabelled version. The intermediate `res1.grb2` is removed.

**Full manual conversion loop** (for all files in a cycle directory):

```bash
cd /home/wrf/WRF_Model/ECMWF/<YYYYMMDDHH>

for f in *.grib2; do
    wgrib2 "$f" -set_grib_type simple -grib_out res1.grb2
    wgrib2 res1.grb2 \
        -if ":soil level 0 - soil level 1" -set_lev "0-0.07 m below ground" \
        -elseif ":soil level 1 - soil level 2" -set_lev "0.07-0.28 m below ground" \
        -elseif ":soil level 2 - soil level 3" -set_lev "0.28-1 m below ground" \
        -elseif ":soil level 3 - soil level 4" -set_lev "1-2.89 m below ground" \
        -endif -grib res.grb2
    mv res.grb2 "$f"
    rm -f res1.grb2
done
```

If `wgrib2` is not installed, the script skips conversion with a warning and the raw ECMWF files will likely fail in `ungrib`.

#### Final copy
If `WRF_COPY_DEST` is set in `ecmwf.cnf`, all converted files are copied via `rsync` to `$WRF_COPY_DEST/<YYYYMMDDHH>/`. A `.converted` marker file is written to the download directory to prevent duplicate runs.

### Command-line flags

```bash
bash get_ecmwf.sh -d          # Dry run: print what would happen, no download
bash get_ecmwf.sh -f 48       # Set max forecast hour to 48
bash get_ecmwf.sh -v 0p4      # Use 0.4° resolution instead of 0.25°
bash get_ecmwf.sh -h "00|12"  # Only allow 00z and 12z cycles
bash get_ecmwf.sh -p ifs      # Set model producer (default: ifs)
```

---

## 4. Run WPS

With the patches from step 1 applied, link the Vtable and run WPS:

```bash
cd $BASE/WPS
ln -sf ungrib/Variable_Tables/Vtable.ECMWF Vtable
./link_grib.csh $BASE/ECMWF/<YYYYMMDDHH>/*.grib2
./ungrib.exe
./metgrid.exe
```

The patched Vtable.ECMWF decodes:
- SKINTEMP (corrected GRIB2 discipline/category/parameter)
- Soil temperature layers: `ST000007`, `ST007028`, `ST028100`, `ST100289` (0–7, 7–28, 28–100, 100–289 cm)
- Soil moisture layers: `SM000007`, `SM007028`, `SM028100`, `SM100289`

---

## 5. Run real.exe and wrf.exe

```bash
cd $BASE/WRF/run
ln -sf ../../WPS/met_em* .
mpirun -np <N> ./real.exe
mpirun -np <N> ./wrf.exe
```

---

## 6. Automation (cron)

To run the download automatically every 6 hours:

```cron
0 1,7,13,19 * * * /home/wrf/WRF_installation/Download/get_ecmwf.sh
```

The download script skips re-download if a `.converted` marker file already exists for that cycle.


