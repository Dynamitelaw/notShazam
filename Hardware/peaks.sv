`include "global_variables.sv"

module peaks( 
		input logic				CLOCK_50,
		input logic 				valid_in,
		input logic[`INPUT_AMPL_WIDTH -1:0] 	fft_in[`FREQS -1:0],
		output logic[`FINAL_AMPL_WIDTH -1:0] 	amplitudes[`PEAKS -1:0],
		output logic[`FREQ_WIDTH -1:0] 		freqs[`PEAKS -1:0]
	);


	logic[`INPUT_AMPL_WIDTH -1:0] 	fft_prev[`FREQS -1:0];
	logic[`INPUT_AMPL_WIDTH -1:0] 	fft_curr[`FREQS -1:0];
	logic[`INPUT_AMPL_WIDTH -1:0] 	fft_next[`FREQS -1:0];
	logic			 	is_peaks[`FREQS -1:0];

	genvar freq;
	generate
	for (freq = 0; freq < `PEAKS; freq=freq+1)
	begin : peak_finders
		if (freq == 0)
			peak_finder(
				.peak(fft_curr[freq]),
				.north(0),
				.south(fft_curr[freq+1]),
				.east(fft_prev[freq]),
				.west(fft_next[freq]),
				.is_peak(is_peaks[freq])
			);
		else if (freq == `PEAKS -1)
			peak_finder(
				.peak(fft_curr[freq]),
				.north(fft_curr[freq-1]),
				.south(0),
				.east(fft_prev[freq]),
				.west(fft_next[freq]),
				.is_peak(is_peaks[freq])
			);
		peak_finder(
			.peak(fft_curr[freq]),
			.north(fft_curr[freq-1]),
			.south(fft_curr[freq+1]),
			.east(fft_prev[freq]),
			.west(fft_next[freq]),
			.is_peak(is_peaks[freq])
		);
	end
	endgenerate

	always_ff @(posedge valid_in) begin
		fft_prev <= fft_curr;
		fft_curr <= fft_next;
		fft_next <= fft_in;	
	end

endmodule


module peak_finder (
		input logic[`INPUT_AMPL_WIDTH -1:0] 	peak,
		input logic[`INPUT_AMPL_WIDTH -1:0] 	north,
		input logic[`INPUT_AMPL_WIDTH -1:0] 	south,
		input logic[`INPUT_AMPL_WIDTH -1:0] 	east,
		input logic[`INPUT_AMPL_WIDTH -1:0] 	west,
		output logic 				is_peak
	);
	assign is_peak = (peak >= north) && (peak >= south) && (peak >= east) && (peak >= west);
endmodule
