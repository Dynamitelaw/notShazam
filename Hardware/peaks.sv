`include "global_variables.sv"

// NOTE: as written, valid_in must be set to low between FFT samples.
module peaks( 
		input logic				CLOCK_50,
		input logic 				valid_in,
		input logic 				reset,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	fft_in[`FREQS -1:0],
		output logic signed [`FINAL_AMPL_WIDTH -1:0] 	amplitudes_out[`PEAKS -1:0],
		output logic [`FREQ_WIDTH -1:0] 		freqs_out[`PEAKS -1:0]
		output logic[`TIME_COUNTER_WIDTH -1:0] 	counter_out
	);

	logic signed [`FINAL_AMPL_WIDTH -1:0] 		amplitudes[`PEAKS -1:0];
	logic [`FREQ_WIDTH -1:0] 		freqs[`PEAKS -1:0];

	logic signed [`INPUT_AMPL_WIDTH -1:0] 	fft_prev[`FREQS -1:0];
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	fft_curr[`FREQS -1:0];
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	fft_next[`FREQS -1:0];
	logic			 	is_peak[`FREQS -1:0];

	genvar freq;
	generate
	for (freq = 0; freq < `FREQS; freq=freq+1)
	begin : peak_finders
		if (freq == 0)
			peak_finder pf(
				.peak(fft_curr[freq]),
				.north(0),
				.south(fft_curr[freq+1]),
				.east(fft_prev[freq]),
				.west(fft_next[freq]),
				.is_peak(is_peak[freq])
			);
		else if (freq == `PEAKS -1)
			peak_finder pf(
				.peak(fft_curr[freq]),
				.north(fft_curr[freq-1]),
				.south(0),
				.east(fft_prev[freq]),
				.west(fft_next[freq]),
				.is_peak(is_peak[freq])
			);
		else
		peak_finder pf(
			.peak(fft_curr[freq]),
			.north(fft_curr[freq-1]),
			.south(fft_curr[freq+1]),
			.east(fft_prev[freq]),
			.west(fft_next[freq]),
			.is_peak(is_peak[freq])
		);
	end
	endgenerate


	always_ff @(posedge valid_in or posedge reset) begin
		if (reset) begin
		fft_prev <= '{`FREQS{0}};
		fft_curr <= '{`FREQS{0}};
		fft_next <= '{`FREQS{0}};
		
		counter_out <= {`TIME_COUNTER_WIDTH{0}};
		amplitudes_out <= '{`PEAKS{0}};
		freqs_out <= '{`PEAKS{0}};
		end
		else 
		begin
		counter_out <= counter_out + 1;
		fft_prev <= fft_curr;
		fft_curr <= fft_next;
		fft_next <= fft_in;	

		amplitudes_out <= amplitudes;
		freqs_out <= freqs;
		end

	end

	integer i;
	always @(*)
	begin
		freqs = '{`PEAKS{0}};
		amplitudes = '{`PEAKS{0}};
		// BIN 1
		for (i = 0; i <= `BIN_1; i=i+1)
		begin : max_bin_1
			if (is_peak[i] && fft_curr[i] > amplitudes[0])
			begin
				amplitudes[0] = fft_curr[i];
				freqs[0]      = i;
			end
		end

		// BIN 2
		for (i = `BIN_1 + 1; i <= `BIN_2; i=i+1)
		begin : max_bin_2
			if (is_peak[i] && fft_curr[i] > amplitudes[1])
			begin
				amplitudes[1] = fft_curr[i];
				freqs[1]      = i;
			end
		end

		// BIN 3
		for (i = `BIN_2 + 1; i <= `BIN_3; i=i+1)
		begin : max_bin_3
			if (is_peak[i] && fft_curr[i] > amplitudes[2])
			begin
				amplitudes[2] = fft_curr[i];
				freqs[2]      = i;
			end
		end

		// BIN 4
		for (i = `BIN_3 + 1; i <= `BIN_4; i=i+1)
		begin : max_bin_4
			if (is_peak[i] && fft_curr[i] > amplitudes[3])
			begin
				amplitudes[3] = fft_curr[i];
				freqs[3]      = i;
			end
		end

		// BIN 5
		for (i = `BIN_4 + 1; i <= `BIN_5; i=i+1)
		begin : max_bin_5
			if (is_peak[i] && fft_curr[i] > amplitudes[4])
			begin
				amplitudes[4] = fft_curr[i];
				freqs[4]      = i;
			end
		end

		// BIN 6
		for (i = `BIN_5 + 1; i <= `BIN_6; i=i+1)
		begin : max_bin_6
			if (is_peak[i] && fft_curr[i] > amplitudes[5])
			begin
				amplitudes[5] = fft_curr[i];
				freqs[6]      = i;
			end
		end

	end
		
endmodule


module peak_finder (
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	peak,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	north,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	south,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	east,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	west,
		output logic				is_peak
	);
	assign is_peak = (peak >= north) && (peak >= south) && (peak >= east) && (peak >= west) ;
endmodule
