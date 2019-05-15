#!/bin/sh
#########################################################
# Run this script to generate ROM files pre-compilation
#########################################################

set -x

#Regenerate ROM files
matlab -nodisplay -nosplash -nodesktop -r "run('../MatlabTesting/GenerateRomFiles.m');exit;"
