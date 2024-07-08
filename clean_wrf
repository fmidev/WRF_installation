#!/bin/bash

find /home/user/out -type f -ctime +5 -o -type l -ctime +5 | xargs -r rm &&
find /home/user/GFS -type f -ctime +5 | xargs -r rm &&
find /home/user/UPP_out -type f -ctime +5 | xargs -r rm &&

find /home/user/out -type d -empty -delete &&
find /home/user/GFS -type d -empty -delete &&
find /home/user/UPP_out -type d -empty -delete

