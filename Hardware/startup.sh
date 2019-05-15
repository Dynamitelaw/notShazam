#!/bin/sh

######################################
# Run this script on DE1 upon startup
######################################

#Set rows and columns for terminal
stty rows 65
stty cols 185

#connect to ethernet
ifup eth0


