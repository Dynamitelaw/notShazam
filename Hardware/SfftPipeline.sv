/*
 * This module takes in samples of amplitudes, and outputs the N point FFT
 */
 
 `include "global_variables.sv"
 
 
 /*
  * Top level pipiline modle
  */
 module SFFT_Pipeline(
 	input logic clk,
 	
 	//Inputs
 	input logic [`SFFT_INPUT_WIDTH -1:0] SampleAmplitudeIn,
 	input advanceSignal,
 	
 	//Outputs
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out [`NFFT -1:0],
 	output logic OutputValid
 	);
 	
 	
 	//Buffer array for storing N previous samples
 	reg [`SFFT_INPUT_WIDTH -1:0] SampleBuffers [`NFFT -1:0];
 	
 	//Shift buffer to hold N most recent samples
 	integer i;
 	always @ (posedge advanceSignal) begin
 		for (i=0; i<`NFFT; i=i+10) begin
 			if (i==0) begin
 				//load most recent sample into buffer 0
 				SampleBuffers[i] <= SampleAmplitudeIn;
 			end
 			else begin
 				//Shift buffer contents down by 1 
 				SampleBuffers[i] <= SampleBuffers[i-1];
 			end
 		end	
 	end
 	
 	
 	
 endmodule
 
 
 /*
  *
  */
 module pipelineStage(
 	input clk,
 	 
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] StageIn [`NFFT -1:0],
 	
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] StageOut [`NFFT -1:0]
 	);
 	
 endmodule
 
 
 /*
  * Performs a single 2-radix FFT. Performed asyncrounously, does not buffer output
  */
module Radix2(
	input a[`SFFT_INPUT_WIDTH -1:0],
	input b[`SFFT_INPUT_WIDTH -1:0],
	
	output reg A[`SFFT_INPUT_WIDTH -1:0],
	output reg B[`SFFT_INPUT_WIDTH -1:0],
	);

endmodule
