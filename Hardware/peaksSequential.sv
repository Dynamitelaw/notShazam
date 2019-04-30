/*
 * This module takes in samples of calculated FFT values, and outputs peak frequencies in each bin
 */
 
`include "global_variables.sv"


 /*
  * Top level peaks module.
  *
  * Samples the calculated FFT values <fft_in> at the rising edge of <valid_in>, and outputs peak frequencies <freqs_out> and their corresponding amplitudes <amplitudes_out>
  *
  * Max sampling frequency ~= CLK_FREQ / (NFFT/2 + MaxBinWidth + 3). Output indeterminate if exceeded.
  */
module peaks( 
	input logic clk,
	input logic reset,
	
	input logic valid_in,
	input logic signed [`INPUT_AMPL_WIDTH -1:0] fft_in[`FREQS -1:0],
		
	output logic signed [`FINAL_AMPL_WIDTH -1:0] amplitudes_out[`PEAKS -1:0],
	output logic [`FREQ_WIDTH -1:0] freqs_out[`PEAKS -1:0],
	output logic[`TIME_COUNTER_WIDTH -1:0] counter_out
	);
	
	
	//_______________________________
	//
	// Sample inputs at valid_in signal
	//_______________________________
	
	logic signed [`INPUT_AMPL_WIDTH -1:0] fft_prev [`FREQS -1:0];
	logic signed [`INPUT_AMPL_WIDTH -1:0] fft_curr [`FREQS +1:0];  //Pad this array with two extra values (0) at the beginning and end
	logic signed [`INPUT_AMPL_WIDTH -1:0] fft_next [`FREQS -1:0];
	
	always_ff @(posedge valid_in or posedge reset) begin
		//Reset
		if (reset) begin
			fft_prev <= '{`FREQS{0}};
			fft_curr <= '{(`FREQS+2){0}};
			fft_next <= '{`FREQS{0}};			
		end
		//Sample input
		else begin
			fft_prev <= fft_curr[`FREQS:1];
			fft_curr[`FREQS:1] <= fft_next;
			fft_next <= fft_in;
		end
	end

	//_______________________________
	//
	// Instaniate peakFinding module
	//_______________________________

	logic signed [`INPUT_AMPL_WIDTH -1:0] 	peakIn;
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	northIn;
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	southIn;
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	eastIn;
	logic signed [`INPUT_AMPL_WIDTH -1:0] 	westIn;
	
	wire isPeakOut;
	
	peak_finder pFinder(
		.peak(peakIn),
		.north(northIn),
		.south(southIn),
		.east(eastIn),
		.west(westIn),
		
		.is_peak(isPeakOut)
		);

	reg [`FREQ_WIDTH:0] peakCounter;
	
	//MUX for peakFinder inputs
	always @ (*) begin
		peakIn = fft_curr[peakCounter];
		northIn = fft_curr[peakCounter-1];
		southIn = fft_curr[peakCounter+1];
		eastIn = fft_prev[peakCounter-1];
		westIn = fft_next[peakCounter-1];
	end
	
	//_______________________________
	//
	// Find local peaks in fft_curr
	//_______________________________

	logic is_peak[`FREQS -1:0];
	 
	reg processingPeaks;
	reg localPeaksValid;
	
	always @ (negedge clk) begin  //using negedge to avoid race condition with valid_in and contention with sampling block
		//Reset
		if (reset) begin
			is_peak <= '{`FREQS{0}};
			localPeaksValid <= 0;
			
			processingPeaks <= 0;
			peakCounter <= 1;
		end
		//New sample. Begin processing
		else if (valid_in) begin
			//NOTE: Presumes valid_in signal is only high for a single cycle
			processingPeaks <= 1;
			peakCounter <= 1;
			localPeaksValid <= 0;
		end
		
		else if (processingPeaks) begin
			is_peak[peakCounter-1] <= isPeakOut;
			if (peakCounter < `FREQS) begin
				peakCounter <= peakCounter+1;
			end
			
			if (peakCounter == `FREQS) begin
				//Finished finding peaks
				localPeaksValid <= 1;
				processingPeaks <= 0;
			end
			else begin
				//More peaks to go
				localPeaksValid <= 0;
			end
		end
	end
	
	//_______________________________
	//
	// Find absolute peaks for bins
	//_______________________________
	 
	logic signed [`INPUT_AMPL_WIDTH -1:0] amplitudes [`PEAKS -1:0];
	logic [`FREQ_WIDTH -1:0] freqs [`PEAKS -1:0];
	
	reg bin1_done;
	reg bin2_done;
	reg bin3_done;
	reg bin4_done;
	reg bin5_done;
	reg bin6_done;
	
	reg [`FREQ_WIDTH -1:0] bin1_counter;
	reg [`FREQ_WIDTH -1:0] bin2_counter;
	reg [`FREQ_WIDTH -1:0] bin3_counter;
	reg [`FREQ_WIDTH -1:0] bin4_counter;
	reg [`FREQ_WIDTH -1:0] bin5_counter;
	reg [`FREQ_WIDTH -1:0] bin6_counter;
	
	reg outputReady;
	
	parameter amplitudeZeros = `INPUT_AMPL_WIDTH-1;
	
	//Instantiate comparator modules
	
	//Bin 1
	logic isLocalPeak_Bin1;
	logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude_Bin1;
	
	//MUX for Bin 1 inputs
	always @ (*) begin
		isLocalPeak_Bin1 = is_peak[bin1_counter];
		newAmplitude_Bin1 = fft_curr[bin1_counter+1];
	end
	
	wire isNewMax_Bin1;
	
	amplitudeComparator comparator_Bin1(
		.isLocalPeak(isLocalPeak_Bin1),
		.currentMax(amplitudes[0]),
		.newAmplitude(newAmplitude_Bin1),
		.isNewMax(isNewMax_Bin1)
		);
	
	//Bin 2
	logic isLocalPeak_Bin2;
	logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude_Bin2;
	
	//MUX for Bin 2 inputs
	always @ (*) begin
		isLocalPeak_Bin2 = is_peak[bin2_counter];
		newAmplitude_Bin2 = fft_curr[bin2_counter+1];
	end
	
	wire isNewMax_Bin2;
	
	amplitudeComparator comparator_Bin2(
		.isLocalPeak(isLocalPeak_Bin2),
		.currentMax(amplitudes[1]),
		.newAmplitude(newAmplitude_Bin2),
		.isNewMax(isNewMax_Bin2)
		);
		
	//Bin 3
	logic isLocalPeak_Bin3;
	logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude_Bin3;
	
	//MUX for Bin 1 inputs
	always @ (*) begin
		isLocalPeak_Bin3 = is_peak[bin3_counter];
		newAmplitude_Bin3 = fft_curr[bin3_counter+1];
	end
	
	wire isNewMax_Bin3;
	
	amplitudeComparator comparator_Bin3(
		.isLocalPeak(isLocalPeak_Bin3),
		.currentMax(amplitudes[2]),
		.newAmplitude(newAmplitude_Bin3),
		.isNewMax(isNewMax_Bin3)
		);
	
	//Bin 4
	logic isLocalPeak_Bin4;
	logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude_Bin4;
	
	//MUX for Bin 4 inputs
	always @ (*) begin
		isLocalPeak_Bin4 = is_peak[bin4_counter];
		newAmplitude_Bin4 = fft_curr[bin4_counter+1];
	end
	
	wire isNewMax_Bin4;
	
	amplitudeComparator comparator_Bin4(
		.isLocalPeak(isLocalPeak_Bin4),
		.currentMax(amplitudes[3]),
		.newAmplitude(newAmplitude_Bin4),
		.isNewMax(isNewMax_Bin4)
		);
	
	//Bin 5
	logic isLocalPeak_Bin5;
	logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude_Bin5;
	
	//MUX for Bin 5 inputs
	always @ (*) begin
		isLocalPeak_Bin5 = is_peak[bin5_counter];
		newAmplitude_Bin5 = fft_curr[bin5_counter+1];
	end
	
	wire isNewMax_Bin5;
	
	amplitudeComparator comparator_Bin5(
		.isLocalPeak(isLocalPeak_Bin5),
		.currentMax(amplitudes[4]),
		.newAmplitude(newAmplitude_Bin5),
		.isNewMax(isNewMax_Bin5)
		);
	
	//Bin 6
	logic isLocalPeak_Bin6;
	logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude_Bin6;
	
	//MUX for Bin 6 inputs
	always @ (*) begin
		isLocalPeak_Bin6 = is_peak[bin6_counter];
		newAmplitude_Bin6 = fft_curr[bin6_counter+1];
	end
	
	wire isNewMax_Bin6;
	
	amplitudeComparator comparator_Bin6(
		.isLocalPeak(isLocalPeak_Bin6),
		.currentMax(amplitudes[5]),
		.newAmplitude(newAmplitude_Bin6),
		.isNewMax(isNewMax_Bin6)
		);
		
		
	always @ (posedge clk) begin
		//Reset
		if (reset || ~localPeaksValid) begin
			amplitudes <= '{`PEAKS{1 << amplitudeZeros}};
			freqs <= '{`PEAKS{0}};
			
			bin1_done <= 0;
			bin2_done <= 1;
			bin3_done <= 1;
			bin4_done <= 1;
			bin5_done <= 1;
			bin6_done <= 1;
			
			bin1_counter <= 0;
			bin2_counter <= `BIN_1 + 1;
			bin3_counter <= `BIN_2 + 1;
			bin4_counter <= `BIN_3 + 1;
			bin5_counter <= `BIN_4 + 1;
			bin6_counter <= `BIN_5 + 1;
			
			outputReady <= 0;
		end
		
		else if (localPeaksValid) begin  //Presumes localPeaksValid is high until a new sample is recieved
			
			//Bin1
			if (~bin1_done) begin
				//Increment counter
				bin1_counter <= bin1_counter + 1;
				//Check for new max
				if (isNewMax_Bin1) begin
					amplitudes[0] <= newAmplitude_Bin1;
					freqs[0]      <= bin1_counter;
				end
				//Check for done condition
				if (bin1_counter == `BIN_1) begin
					bin1_done <= 1;
				end
			end
			
			//Bin2
			if (~bin2_done) begin
				//Increment counter
				bin2_counter <= bin2_counter + 1;
				//Check for new max
				if (isNewMax_Bin2) begin
					amplitudes[1] <= newAmplitude_Bin2;
					freqs[1]      <= bin2_counter;
				end
				//Check for done condition
				if (bin2_counter == `BIN_2) begin
					bin2_done <= 1;
				end
			end
			
			//Bin3
			if (~bin3_done) begin
				//Increment counter
				bin3_counter <= bin3_counter + 1;
				//Check for new max
				if (isNewMax_Bin3) begin
					amplitudes[2] <= newAmplitude_Bin3;
					freqs[2]      <= bin3_counter;
				end
				//Check for done condition
				if (bin3_counter == `BIN_3) begin
					bin3_done <= 1;
				end
			end
			
			//Bin4
			if (~bin4_done) begin
				//Increment counter
				bin4_counter <= bin4_counter + 1;
				//Check for new max
				if (isNewMax_Bin4) begin
					amplitudes[3] <= newAmplitude_Bin4;
					freqs[3]      <= bin4_counter;
				end
				//Check for done condition
				if (bin4_counter == `BIN_4) begin
					bin4_done <= 1;
				end
			end
			
			//Bin5
			if (~bin5_done) begin
				//Increment counter
				bin5_counter <= bin5_counter + 1;
				//Check for new max
				if (isNewMax_Bin5) begin
					amplitudes[4] <= newAmplitude_Bin5;
					freqs[4]      <= bin5_counter;
				end
				//Check for done condition
				if (bin5_counter == `BIN_5) begin
					bin5_done <= 1;
				end
			end
			
			//Bin6
			if (~bin6_done) begin
				//Increment counter
				bin6_counter <= bin6_counter + 1;
				//Check for new max
				if (isNewMax_Bin6) begin
					amplitudes[5] <= newAmplitude_Bin6;
					freqs[5]      <= bin6_counter;
				end
				//Check for done condition
				if (bin6_counter == `BIN_6) begin
					bin6_done <= 1;
				end
			end
			
			//Check if we're done finding maxima
			if (bin1_done && bin2_done && bin3_done && bin4_done && bin5_done && bin6_done) begin
				outputReady <= 1;
			end
		end
	end
	
	//_______________________________
	//
	// Write module output
	//_______________________________

	integer j;
	always @ (posedge outputReady or posedge reset) begin
		//Reset
		if (reset) begin
			counter_out <= `TIME_COUNTER_WIDTH'b0;
			amplitudes_out <= '{`PEAKS{0}};
			freqs_out <= '{`PEAKS{0}};
		end
		
		else begin
			counter_out <= counter_out + 1;
			
			for (j = 0; j < `PEAKS; j = j + 1) begin 
				amplitudes_out[j] <= amplitudes[j][`INPUT_AMPL_WIDTH -1: `INPUT_AMPL_WIDTH - `FINAL_AMPL_WIDTH];
			end
			freqs_out <= freqs;
		end
	end
	
	
	//_______________________________
	//
	// Simulation probes
	//_______________________________
	/*
	wire signed [`INPUT_AMPL_WIDTH -1:0] fft_in_PROBE [`FREQS -1:0];
	wire signed [`INPUT_AMPL_WIDTH -1:0] fft_prev_PROBE [`FREQS -1:0];
	wire signed [`INPUT_AMPL_WIDTH -1:0] fft_curr_PROBE [`FREQS +1:0];  //Pad this array with two extra values (0) at the beginning and end
	wire signed [`INPUT_AMPL_WIDTH -1:0] fft_next_PROBE [`FREQS -1:0];
	wire is_peak_PROBE [`FREQS -1:0];
	wire signed [`INPUT_AMPL_WIDTH -1:0] amplitudes_PROBE [`PEAKS -1:0];
	wire [`FREQ_WIDTH -1:0] freqs_PROBE [`PEAKS -1:0];
	
	assign fft_in_PROBE = fft_in;
	assign fft_prev_PROBE = fft_prev;
	assign fft_curr_PROBE = fft_curr;
	assign fft_next_PROBE = fft_next;
	assign is_peak_PROBE = is_peak;
	assign amplitudes_PROBE = amplitudes;
	assign freqs_PROBE = freqs;
	*/
endmodule  //peaks


/*
 * Compares an amplitude to its cardinal neighbors to determine if it's a local maxima
 */
module peak_finder (
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	peak,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	north,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	south,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	east,
		input logic signed [`INPUT_AMPL_WIDTH -1:0] 	west,
		
		output logic				is_peak
	);
	assign is_peak = (peak >= north) && (peak >= south) && (peak >= east) && (peak >= west) ;
	//assign is_peak = (peak > north) && (peak > south) && (peak > east) && (peak > west) ;
endmodule  //peak_finder


/*
 * 
 */
module amplitudeComparator(
	input isLocalPeak,
	input logic signed [`INPUT_AMPL_WIDTH -1:0] currentMax,
	input logic signed [`INPUT_AMPL_WIDTH -1:0] newAmplitude,
	
	output logic isNewMax
	);
	assign isNewMax = isLocalPeak && (newAmplitude > currentMax);
endmodule
