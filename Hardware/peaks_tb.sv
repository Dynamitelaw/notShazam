`include "peaks.sv"

module peaks_tb();

	logic				CLOCK_50 = 0;
	logic 				valid_in;
	logic 				reset;
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	fft_in[`FREQS -1:0];
	logic signed [`FINAL_AMPL_WIDTH -1:0] 	amplitudes_out[`PEAKS -1:0];
	logic[`FREQ_WIDTH -1:0] 	freqs_out[`PEAKS -1:0];


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
		#2
		reset = 0;
		#10

		fft_in = '{	0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 6


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
		# 6
		

		#10
		fft_in = '{	0, 1, 0, 0,
				0, 0, 0, 0,
				6, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 6


		fft_in = '{	0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		# 6


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
		# 6
		

		#10
		fft_in = '{	0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0,
				0, 0, 0, 0};
		valid_in = 1;
		#2
		valid_in = 0;
		#2

		valid_in = 1;
		#2
		valid_in = 0;

		#2
		valid_in = 1;
		#2
		valid_in = 0;

		#2
		valid_in = 1;
		#2
		valid_in = 0;

		#2
		valid_in = 1;
		#2
		valid_in = 0;

		$stop;

	end 


	always begin
		#1
		CLOCK_50 = ~CLOCK_50;
	end
endmodule
