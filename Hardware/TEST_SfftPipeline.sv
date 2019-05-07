/*
 * Testbench for SFFT pipeline
 * 
 * Tested using the following macors:
	// FFT Macros
	`define NFFT 32 // if change this, change FREQ_WIDTH. Must be power of 2
	`define nFFT 5  //log2(NFFT)

	`define FREQS (`NFFT / 2)
	`define FREQ_WIDTH 8 // if change NFFT, change this

	`define FINAL_AMPL_WIDTH 32 // Must be less than or equal to INPUT_AMPL_WIDTH
	`define INPUT_AMPL_WIDTH 32 
	`define TIME_COUNTER_WIDTH 32

	`define PEAKS 6 // Changing this requires many changes in code

	`define RUNNING_SIMULATION  //define this to change ROM file locations to absolute paths fo vsim
	`define SFFT_INPUT_WIDTH 24
	`define SFFT_OUTPUT_WIDTH `INPUT_AMPL_WIDTH
	`define SFFT_FIXEDPOINT_INPUTSCALING  //define this macro if you want to scale adc inputs to match FixedPoint magnitudes. Increases accuracy, but could lead to overflow
	`define SFFT_FIXED_POINT_ACCURACY 7
	`define SFFT_STAGECOUNTER_WIDTH 5  //>= log2(nFFT)

	//`define SFFT_DOWNSAMPLE_PRE  //define this macro if you want to downsample the incoming audio BEFORE the FFT calculation
	`define SFFT_DOWNSAMPLE_PRE_FACTOR 3
	`define nDOWNSAMPLE_PRE 2  // >= log2(SFFT_DOWNSAMPLE_PRE_FACTOR)

	//`define SFFT_DOWNSAMPLE_POST  //define this macro if you want to downsample the outgoing FFT calculation (will skip calculations)
	`define SFFT_DOWNSAMPLE_POST_FACTOR 5
	`define nDOWNSAMPLE_POST 3  // >= log2(SFFT_DOWNSAMPLE_POST_FACTOR)

	// Audio Codec Macros
	`define AUDIO_IN_GAIN 9'h010
	`define AUDIO_OUT_GAIN 9'h061
 */
 
`include "global_variables.sv"
//`include "SfftPipeline.sv"
`include "SfftPipeline_SingleStage.sv"

`define CALCULATION_DELAY #400
 
 module Sfft_Testbench();
 	reg reset = 0;
	reg clk = 0;
	
	//Inputs
	reg [`SFFT_INPUT_WIDTH -1:0] SampleAmplitudeIn = 0;
 	reg advanceSignal =0;
 	reg OutputBeingRead = 0;
 	
 	//Outputs
 	logic [`nFFT -1:0] output_address = 0;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_OutReal;
 	wire OutputValid;
 
 	SFFT_Pipeline sfft(
	 	.clk(clk),
	 	.reset(reset),
	 	
	 	.SampleAmplitudeIn(SampleAmplitudeIn),
	 	.advanceSignal(advanceSignal),
	 	
	 	.OutputBeingRead(OutputBeingRead),
	 	.output_address(output_address),
	 	.SFFT_OutReal(SFFT_OutReal),
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
		
		//Load in samples 100, 53, 29, 47, 30, 91, 69, 64, 50, 28, 8, 4, 45, 59, 30, 10, 74, 31, 24, 46, 71, 81, 92, 24, 93, 34, 52, 47, 5, 96, 81, 70
		SampleAmplitudeIn <= 70;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 81;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 96;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 5;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 47;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 52;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 34;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 93;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		//Load in samples 100, 53, 29, 47, 30, 91, 69, 64, 50, 28, 8, 4, 45, 59, 30, 10, 74, 31, 24, 46, 71, 81, 92, 24, 93, 34, 52, 47, 5, 96, 81, 70
		SampleAmplitudeIn <= 24;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 92;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 81;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 71;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 46;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 24;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 31;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 74;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		//Load in samples 100, 53, 29, 47, 30, 91, 69, 64, 50, 28, 8, 4, 45, 59, 30, 10, 74, 31, 24, 46, 71, 81, 92, 24, 93, 34, 52, 47, 5, 96, 81, 70
		SampleAmplitudeIn <= 10;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 30;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 59;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 45;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 4;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 8;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 28;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 50;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		//Load in samples 100, 53, 29, 47, 30, 91, 69, 64, 50, 28, 8, 4, 45, 59, 30, 10, 74, 31, 24, 46, 71, 81, 92, 24, 93, 34, 52, 47, 5, 96, 81, 70
		SampleAmplitudeIn <= 64;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 69;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 91;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 30;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 47;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 29;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 53;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		SampleAmplitudeIn <= 100;
		advanceSignal <= 0;
		`CALCULATION_DELAY  //Wait for calculation to complete
		#1 //posedge
		advanceSignal <= 1;
		#1 //negedge
		
		advanceSignal <= 0;
		
		`CALCULATION_DELAY
		$stop;
	end
	
	//Clock toggling
	always begin
		#1  //2-step period
		clk <= ~clk;
	end
	
 endmodule
