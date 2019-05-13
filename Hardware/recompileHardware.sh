#!/bin/sh
set -x

date

#Delete old RBF in case git ignores the new one
git rm output_files/*.rbf
git commit -m "deleted old rbf"

#CAT globalVariables used in compilation
cat global_variables.sv

#Regenerate ROM files
matlab -nodisplay -nosplash -nodesktop -r "run('../MatlabTesting/GenerateRomFiles.m');exit;"

#Recompile Verilog code
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

#Beep to signal completion
echo -ne '\007'
echo -ne '\007'
echo -ne '\007'
