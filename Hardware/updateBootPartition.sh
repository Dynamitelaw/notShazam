#!/bin/sh
###########################################
# Run this script on DE1 to load new rbf/dtb
###########################################

set -x

#Mount boot partition
echo "#############################"
mount /dev/mmcblk0p1 /mnt

#Copy over rbf and and dtb files
echo "#############################"
cp output_files/soc_system.rbf /mnt/soc_system.rbf
cp soc_system.dtb /mnt/soc_system.dtb

#Reboot
reboot
