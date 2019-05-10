ifneq (${KERNELRELEASE},)

# KERNELRELEASE defined: we are being compiled as part of the Kernel
        obj-m := fft_accelerator.o

else
# We are being compiled as a module: use the Kernel build system

	KERNEL_SOURCE := /usr/src/linux-headers-$(shell uname -r)
        PWD := $(shell pwd)
        
CC  = g++
CXX = g++ -O0

# Comment out one of the following 2 lines to enable/disable BASIC4TRACE.
#INCLUDES = -DBASIC4TRACE
INCLUDES =

CFLAGS   = -g -Wall $(INCLUDES)
CXXFLAGS = -g -Wall $(INCLUDES) -std=c++0x


executables = recognize usr
objects = recognize.o usr.o 

.PHONY: default
default: $(executables)

$(executables): recognize.o usr.o 

$(objects): fft_accelerator.h

.PHONY: clean
clean:
	rm -f *~ a.out core $(objects) $(executables)

.PHONY: all
all: clean default

#===============================================================

