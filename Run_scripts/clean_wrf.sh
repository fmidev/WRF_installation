#!/bin/bash

# ===============================================
# Clean old data
# Author: Mikael Hasu
# Date: November 2024
# ===============================================

find /home/wrf/WRF_Model/GFS -type f -ctime +0 | xargs -r rm
find /home/wrf/WRF_Model/GFS -type d -empty -delete
find /home/wrf/WRF_Model/DA_input/rc -type f -ctime +2 -name "*wrfout*" | xargs -r rm
find /home/wrf/WRF_Model/out -type f -ctime +2 -o -type l -ctime +2 | xargs -r rm 
find /home/wrf/WRF_Model/out -type d -empty -delete 
find /home/wrf/WRF_Model/UPP_out -type f -ctime +5 | xargs -r rm
find /home/wrf/WRF_Model/UPP_out -type d -empty -delete