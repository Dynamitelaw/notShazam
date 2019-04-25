#!/bin/sh
set -x

#Regenerate ROM files
matlab -nodisplay -nosplash -nodesktop -r "run('../MatlabTesting/GenerateRomFiles.m');exit;"

#Recombile Verilog code
echo "#############################"
make clean
make quartus

#Create rbf
echo "#############################"
make rbf
make dtb

#Git push
echo "#############################"
echo "Upload to Github"
git pull
git add output_files/*.rbf
git add *.dtb
git commit -m "compiled new version of hardware files"
git push
