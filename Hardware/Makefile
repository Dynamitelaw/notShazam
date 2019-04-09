.PHONY: program clean

# Program the FPGA through the USB Blaster connection
# It is the second thing on the JTAG chain (the HPS block is first), hence @2

program : output_files/lab1.sof
	quartus_pgm -c 1 -m jtag -o "p;output_files/FFT_Accelerator.sof@2"

# Compile the project

output_files/lab1.sof : FFT_Accelerator.qpf FFT_Accelerator.sv
	quartus_sh --flow compile FFT_Accelerator

# Create the project files from a Tcl script

FFT_Accelerator.qpf FFT_Accelerator.qsf FFT_Accelerator.sdc : de1-soc-project.tcl
	quartus_sh -t de1-soc-project.tcl

# Create a .tar.gz file of the contents

TARFILES = Makefile FFT_Accelerator.sv de1-soc-project.tcl

lab1.tar.gz : $(TARFILES)
	mkdir FFT_Accelerator
	ln $(TARFILES) FFT_Accelerator
	tar zcf lab1.tar.gz FFT_Accelerator
	rm -rf FFT_Accelerator

clean :
	rm -rf db incremental_db output_files FFT_Accelerator.qpf FFT_Accelerator.qsf FFT_Accelerator.sdc \
	FFT_Accelerator.qws c5_pin_model_dump.txt
