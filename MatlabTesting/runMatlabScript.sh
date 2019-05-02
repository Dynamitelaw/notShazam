#!/bin/sh
set -x

#Regenerate ROM files
matlab -nodisplay -nosplash -nodesktop -r "run('../MatlabTesting/GenerateRomFiles.m');exit;"
