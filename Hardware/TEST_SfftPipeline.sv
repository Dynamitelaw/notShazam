/*
 * Testbench for SFFT pipeline
 * 
 * Tested using the following macors:
	// FFT Macros
	`define NFFT 8 // if change this, change FREQ_WIDTH. Must be power of 2
	`define nFFT 3  //log2(NFFT)

	`define FREQS (`NFFT / 2)
	`define FREQ_WIDTH 4 // if change NFFT, change this

	`define FINAL_AMPL_WIDTH 24
	`define INPUT_AMPL_WIDTH 32

	`define PEAKS 6 // Changing this requires many changes in code

	`define SFFT_INPUT_WIDTH 24
	`define SFFT_OUTPUT_WIDTH `INPUT_AMPL_WIDTH
	`define SFFT_FIXED_POINT_ACCURACY 7
 */
 
`include "global_variables.sv"
//`include "SfftPipeline.sv"
`include "SfftPipeline_SingleStage.sv"
 
 module Sfft_Testbench();
 	reg reset = 0;
	reg clk = 0;
	
	//Inputs
	reg [`SFFT_INPUT_WIDTH -1:0] SampleAmplitudeIn = 0;
 	reg advanceSignal =0;
 	
 	//Outputs
 	wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out [`NFFT -1:0];
 	wire OutputValid;
 
 	SFFT_Pipeline sfft(
	 	.clk(clk),
	 	.reset(reset),
	 	
	 	.SampleAmplitudeIn(SampleAmplitudeIn),
	 	.advanceSignal(advanceSignal),
	 	
	 	.SFFT_Out(SFFT_Out),
	 	.OutputValid(OutputValid)
	 	);
	 	
 	initial
	begin
		clk <= 0;
		reset <= 1; //Reset all modules
		
		#1 //posedge
		#1 //negedge
		
		#1 //posedge
		#1 //negedge
		
		reset <= 0;
		
		//Load in samples 11, 85, 23, 33, 6, 90, 77, 61
		SampleAmplitudeIn <= 61;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 77;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 90;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 6;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 33;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 23;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 85;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 11;
		advanceSignal <= 0;
		#120  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		advanceSignal <= 0;
		
		#300
		$stop;
	end
	
	//Clock toggling
	always begin
		#1  //2-step period
		clk <= ~clk;
	end
	
 endmodule
