#!/bin/sh
set -x

date

#CAT globalVariables used in compilation
cat global_variables.sv

#Regenerate ROM files
matlab -nodisplay -nosplash -nodesktop -r "run('../MatlabTesting/GenerateRomFiles.m');exit;"

#Recombile Verilog code
embedded_command_shell.sh 
echo "#############################"
date
make clean
make quartus

#Create rbf
echo "#############################"
date
make rbf
make dtb

#Git push
echo "#############################"
date
echo "Upload to Github"
git pull
git add output_files/*.rbf
git add *.dtb
git commit -m "compiled new version of hardware files"
git push
date
