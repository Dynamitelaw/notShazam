/*
Tested with the following global variables:

// FFT Macros
`define NFFT 32 // if change this, change FREQ_WIDTH. Must be power of 2
`define nFFT 5  //log2(NFFT)

`define FREQS (`NFFT / 2)
`define FREQ_WIDTH 4 // if change NFFT, change this

`define FINAL_AMPL_WIDTH 32 // Must be less than or equal to INPUT_AMPL_WIDTH
`define INPUT_AMPL_WIDTH 32 
`define TIME_COUNTER_WIDTH 32

`define PEAKS 6 // Changing this requires many changes in code

`define SFFT_INPUT_WIDTH 24
`define SFFT_OUTPUT_WIDTH `INPUT_AMPL_WIDTH
`define SFFT_FIXED_POINT_ACCURACY 7

// Audio Codec Macros
`define AUDIO_IN_GAIN 9'h014
`define AUDIO_OUT_GAIN 9'h061

// BINS NFFT=16
`define BIN_1 1
`define BIN_2 3
`define BIN_3 5
`define BIN_4 8
`define BIN_5 12
`define BIN_6 15
*/


//`include "peaks.sv"
`include "peaksSequential.sv"

module peaks_tb();

	logic				clk = 0;
	logic 				valid_in;
	logic 				reset;
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	fft_in[`FREQS -1:0];
	logic signed [`FINAL_AMPL_WIDTH -1:0] 	amplitudes_out[`PEAKS -1:0];
	logic[`FREQ_WIDTH -1:0] 	freqs_out[`PEAKS -1:0];
	logic[`TIME_COUNTER_WIDTH -1:0] counter_out;


	genvar j;
	generate
	for (j = 0; j < `FREQS; j=j+1)
	begin : in
		wire [`INPUT_AMPL_WIDTH -1:0] fft = fft_in[j];
	end

	for (j = 0; j < `PEAKS; j=j+1)
	begin : out
		wire [`FINAL_AMPL_WIDTH -1:0] ampl = amplitudes_out[j];
		wire [`FREQ_WIDTH -1:0] freq = freqs_out[j];
	end
	endgenerate

	peaks p(.*);

	initial begin
		reset = 0;
		valid_in = 0;
		#2
		reset = 1;
		#4
		reset = 0;
		#9

		fft_in = '{	0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 60


		#10
		fft_in = '{	1, 2, 
				3, 4,
				5, 4, 
				7, 0, -8, 
				0, 0, 0, 0, 
				1, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 60
		

		#10
		fft_in = '{	0, 1, 0, 0,
				0, 0, 0, 0,
				6, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 60


		fft_in = '{	0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 60


		#10
		fft_in = '{	1, 2, 
				3, 4,
				5, 4, 
				7, 0, 8, 
				0, 0, 0, 0, 
				1, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 60
		

		#10
		fft_in = '{	0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0};

		#2
		valid_in = 1;
		#2
		valid_in = 0;
		# 60

		$stop;

	end 


	always begin
		#1
		clk = ~clk;
	end
endmodule
