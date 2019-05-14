/*
 * This module takes in samples of amplitudes, and outputs the N point FFT
 */
 
`include "global_variables.sv"

//`ifdef RUNNING_SIMULATION
`include "bram.sv"
//`else
	//`include "bramNewer.v"
//`endif
 
 
 /*
  * Top level SFFT pipeline module.
  *
  * Samples the input signal <SampleAmplitudeIn> at the rising edge of <advanceSignal>. Begins processing the FFT immediately.
  * Only outputs the real components of the FFT result. Will raise <OutputValid> high for 1 cycle when the output is finished.
  *
  * Output port provides access to an internal BRAM module where the results are stored. The reader must provide the address of the result they wish to read.
  *
  * Max sampling frequency ~= (CLK_FREQ*DOWNSAMPLE_PRE_FACTOR*DOWNSAMPLE_POST_FACTOR) / (log2(NFFT)*NFFT/2+2). Output indeterminate if exceeded.
  */
 module SFFT_Pipeline(
 	input clk,
 	input reset,
 	
 	//Inputs
 	input [`SFFT_INPUT_WIDTH -1:0] SampleAmplitudeIn,
 	input advanceSignal,
 	
 	//Output BRAM IO
 	input logic OutputBeingRead,
 	output logic outputReadError,
 	input logic [`nFFT -1:0] output_address,
 	output reg [`SFFT_OUTPUT_WIDTH -1:0] SFFT_OutReal,
 	output logic OutputValid,
 	output reg [`SFFT_OUTPUT_WIDTH -1:0] Output_Why
 	);
 	
 	
	//___________________________
	//
	// ROM for static parameters
	//___________________________
	
	reg [`nFFT -1:0] shuffledInputIndexes [`NFFT -1:0];
	
	reg [`nFFT -1:0] kValues [`nFFT*(`NFFT / 2) -1:0];
	
	reg [`nFFT -1:0] aIndexes [`nFFT*(`NFFT / 2) -1:0];
	reg [`nFFT -1:0] bIndexes [`nFFT*(`NFFT / 2) -1:0];
	
	reg [`SFFT_FIXED_POINT_ACCURACY:0] realCoefficents [(`NFFT / 2) -1:0];
	reg [`SFFT_FIXED_POINT_ACCURACY:0] imagCoefficents [(`NFFT / 2) -1:0];
	
	//Load values into ROM from generated text files
	initial begin
`ifdef RUNNING_SIMULATION
		//NOTE: These filepaths must be changed to their absolute local paths if simulating with Vsim. Otherwise they should be relative to Hardware directory
		//NOTE: If simulating with Vsim, make sure to run the Matlab script GenerateRomFiles.m if you change any global variables
		
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/InputShuffledIndexes.txt", shuffledInputIndexes, 0);
		
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/Ks.txt", kValues, 0);
		
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/aIndexes.txt", aIndexes, 0);
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/bIndexes.txt", bIndexes, 0);
		
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/realCoefficients.txt", realCoefficents, 0);
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/imaginaryCoefficients.txt", imagCoefficents, 0);
`else
		$readmemh("GeneratedParameters/InputShuffledIndexes.txt", shuffledInputIndexes, 0);
		
		$readmemh("GeneratedParameters/Ks.txt", kValues, 0);
		
		$readmemh("GeneratedParameters/aIndexes.txt", aIndexes, 0);
		$readmemh("GeneratedParameters/bIndexes.txt", bIndexes, 0);
		
		$readmemh("GeneratedParameters/realCoefficients.txt", realCoefficents, 0);
		$readmemh("GeneratedParameters/imaginaryCoefficients.txt", imagCoefficents, 0);
`endif
	end
	
	//Map 2D ROM arrays into 3D
	wire [`nFFT -1:0] kValues_Mapped [`nFFT -1:0] [(`NFFT / 2) -1:0];
	wire [`nFFT -1:0] aIndexes_Mapped [`nFFT -1:0] [(`NFFT / 2) -1:0];
	wire [`nFFT -1:0] bIndexes_Mapped [`nFFT -1:0] [(`NFFT / 2) -1:0];
	
	genvar stage;
	generate
		for (stage=0; stage<`nFFT; stage=stage+1) begin : ROM_mapping
			assign kValues_Mapped[stage] = kValues[(stage+1)*(`NFFT / 2)-1 : stage*(`NFFT / 2)];
			assign aIndexes_Mapped[stage] = aIndexes[(stage+1)*(`NFFT / 2)-1 : stage*(`NFFT / 2)];
			assign bIndexes_Mapped[stage] = bIndexes[(stage+1)*(`NFFT / 2)-1 : stage*(`NFFT / 2)];
		end
	endgenerate
	
	//_________________________
	//
	// Input Sampling
	//_________________________
	 	
 	wire [`SFFT_INPUT_WIDTH -1:0] SampleAmplitudeIn_Processed;
 	reg advanceSignal_Intermediate;
 	reg advanceSignal_Processed;
 	
 	/*
 	 * Implement downsampling if specified
 	 */
 	 
 	//Pre downsampling
`ifdef SFFT_DOWNSAMPLE_PRE
	//Shift buffer to hold SFFT_DOWNSAMPLE_PRE_FACTOR most recent raw samples
	reg [`SFFT_INPUT_WIDTH -1:0] WindowBuffers [`SFFT_DOWNSAMPLE_PRE_FACTOR -1:0] = '{default:0};
 	integer m;
 	always @ (posedge advanceSignal) begin
 		for (m=0; m<`SFFT_DOWNSAMPLE_PRE_FACTOR; m=m+1) begin
 			if (m==0) begin
 				//load most recent raw sample into buffer 0
 				WindowBuffers[m] <= SampleAmplitudeIn;
 			end
 			else begin
 				//Shift buffer contents down by 1 
 				WindowBuffers[m] <= WindowBuffers[m-1];
 			end
 		end	
 	end
 	
 	//Take moving average of window. Acts as lowpass filter
 	logic [`SFFT_INPUT_WIDTH + `nDOWNSAMPLE_PRE -1:0] movingSum = 0;
 	always @(posedge advanceSignal) begin
 		movingSum = movingSum + SampleAmplitudeIn - WindowBuffers[`SFFT_DOWNSAMPLE_PRE_FACTOR -1];
 	end
 	
 	logic [`SFFT_INPUT_WIDTH + `nDOWNSAMPLE_PRE -1:0] movingAverage;
 	always @(*) begin
 		movingAverage = movingSum/`SFFT_DOWNSAMPLE_PRE_FACTOR;
 	end
 	
 	assign SampleAmplitudeIn_Processed = movingAverage[`SFFT_INPUT_WIDTH -1:0];  //right shift by nDOWNSAMPLE_PRE to divide sum into average
 	
 	//Counter for input downsampling
 	reg [`nDOWNSAMPLE_PRE -1:0] downsamplePRECounter = 0;
 	always @ (posedge advanceSignal) begin
 		if (downsamplePRECounter == `SFFT_DOWNSAMPLE_PRE_FACTOR -1) begin
			downsamplePRECounter <= 0;
		end
		else begin
			downsamplePRECounter <= downsamplePRECounter + 1;
		end
	end
	
	always @ (posedge clk) begin
		advanceSignal_Intermediate <= (downsamplePRECounter == `SFFT_DOWNSAMPLE_PRE_FACTOR -1) && advanceSignal;
	end
`else
	assign SampleAmplitudeIn_Processed = SampleAmplitudeIn;
	
	always @(*) begin
		advanceSignal_Intermediate = advanceSignal;
	end 
`endif

	//Post downsampling
`ifdef SFFT_DOWNSAMPLE_POST
	reg [`nDOWNSAMPLE_POST -1:0] downsamplePOSTCounter = 0;
	always @ (posedge advanceSignal_Intermediate) begin
		if (downsamplePOSTCounter == `SFFT_DOWNSAMPLE_POST_FACTOR -1) begin
			downsamplePOSTCounter <= 0;
		end
		else begin
			downsamplePOSTCounter <= downsamplePOSTCounter + 1;
		end
	end
	
	always @ (posedge clk) begin
		advanceSignal_Processed <= (downsamplePOSTCounter == `SFFT_DOWNSAMPLE_POST_FACTOR -1) && advanceSignal_Intermediate;
	end
`else
	always @(*) begin
 		advanceSignal_Processed = advanceSignal_Intermediate;
 	end
`endif
 	
 	
 	//Shift buffer to hold N most recent samples
 	//reg [`SFFT_INPUT_WIDTH -1:0] SampleBuffers [`NFFT -1:0] = '{default:0};
 	
 	reg [`SFFT_INPUT_WIDTH -1:0] SampleBuffers [511:0] = '{24'd0, 24'd21, 
24'd33, 24'd23, 24'd19, 24'd10, 24'd42, 24'd26, 24'd6, 24'd31, 24'd5, 24'd3, 24'd33, 24'd13, 24'd19, 24'd25, 24'd34, 24'd42, 24'd33, 24'd44, 24'd27, 24'd25, 24'd17, 24'd19, 24'd42, 24'd26, 24'd26, 24'd9, 24'd44, 24'd6, 24'd4, 24'd12, 
24'd26, 24'd19, 24'd31, 24'd2, 24'd32, 24'd17, 24'd41, 24'd7, 24'd41, 24'd13, 24'd8, 24'd1, 24'd24, 24'd41, 24'd23, 24'd40, 24'd8, 24'd21, 24'd0, 24'd43, 24'd27, 24'd32, 24'd12, 24'd9, 24'd34, 24'd2, 24'd5, 24'd17, 24'd6, 24'd23, 
24'd12, 24'd11, 24'd27, 24'd35, 24'd14, 24'd8, 24'd30, 24'd9, 24'd38, 24'd27, 24'd1, 24'd4, 24'd15, 24'd35, 24'd23, 24'd6, 24'd15, 24'd3, 24'd15, 24'd2, 24'd8, 24'd39, 24'd19, 24'd34, 24'd10, 24'd27, 24'd12, 24'd5, 24'd31, 24'd22, 
24'd5, 24'd29, 24'd43, 24'd24, 24'd15, 24'd16, 24'd16, 24'd40, 24'd26, 24'd41, 24'd44, 24'd18, 24'd3, 24'd8, 24'd44, 24'd43, 24'd4, 24'd14, 24'd1, 24'd3, 24'd18, 24'd9, 24'd15, 24'd36, 24'd6, 24'd19, 24'd44, 24'd38, 24'd0, 24'd24, 
24'd2, 24'd19, 24'd42, 24'd18, 24'd15, 24'd8, 24'd16, 24'd40, 24'd2, 24'd21, 24'd41, 24'd38, 24'd8, 24'd39, 24'd13, 24'd5, 24'd16, 24'd15, 24'd37, 24'd39, 24'd41, 24'd28, 24'd36, 24'd0, 24'd22, 24'd4, 24'd30, 24'd39, 24'd2, 24'd30, 
24'd5, 24'd22, 24'd7, 24'd1, 24'd14, 24'd14, 24'd6, 24'd20, 24'd1, 24'd24, 24'd37, 24'd35, 24'd22, 24'd15, 24'd12, 24'd43, 24'd38, 24'd38, 24'd15, 24'd31, 24'd37, 24'd1, 24'd4, 24'd14, 24'd1, 24'd37, 24'd7, 24'd18, 24'd12, 24'd24, 
24'd4, 24'd20, 24'd7, 24'd34, 24'd5, 24'd9, 24'd4, 24'd38, 24'd17, 24'd33, 24'd38, 24'd42, 24'd28, 24'd34, 24'd16, 24'd2, 24'd18, 24'd37, 24'd13, 24'd13, 24'd8, 24'd18, 24'd20, 24'd28, 24'd9, 24'd13, 24'd28, 24'd10, 24'd23, 24'd39, 
24'd32, 24'd42, 24'd1, 24'd37, 24'd20, 24'd42, 24'd14, 24'd6, 24'd10, 24'd7, 24'd30, 24'd37, 24'd41, 24'd0, 24'd4, 24'd29, 24'd36, 24'd32, 24'd27, 24'd9, 24'd0, 24'd16, 24'd9, 24'd36, 24'd38, 24'd11, 24'd13, 24'd14, 24'd33, 24'd3, 
24'd37, 24'd5, 24'd34, 24'd6, 24'd25, 24'd37, 24'd1, 24'd19, 24'd35, 24'd19, 24'd16, 24'd25, 24'd4, 24'd12, 24'd35, 24'd29, 24'd30, 24'd13, 24'd20, 24'd35, 24'd1, 24'd10, 24'd17, 24'd25, 24'd11, 24'd7, 24'd27, 24'd6, 24'd37, 24'd0, 
24'd26, 24'd19, 24'd22, 24'd5, 24'd37, 24'd30, 24'd18, 24'd1, 24'd13, 24'd39, 24'd16, 24'd15, 24'd26, 24'd21, 24'd6, 24'd35, 24'd15, 24'd2, 24'd18, 24'd11, 24'd25, 24'd19, 24'd0, 24'd29, 24'd37, 24'd25, 24'd4, 24'd19, 24'd20, 24'd39, 
24'd42, 24'd27, 24'd35, 24'd35, 24'd18, 24'd13, 24'd12, 24'd39, 24'd23, 24'd23, 24'd7, 24'd38, 24'd23, 24'd29, 24'd7, 24'd31, 24'd40, 24'd43, 24'd38, 24'd33, 24'd29, 24'd5, 24'd7, 24'd4, 24'd19, 24'd36, 24'd11, 24'd5, 24'd30, 24'd35, 
24'd26, 24'd25, 24'd12, 24'd41, 24'd27, 24'd43, 24'd17, 24'd19, 24'd42, 24'd41, 24'd24, 24'd43, 24'd17, 24'd23, 24'd8, 24'd43, 24'd36, 24'd33, 24'd18, 24'd40, 24'd1, 24'd43, 24'd4, 24'd25, 24'd41, 24'd44, 24'd0, 24'd22, 24'd16, 24'd14, 
24'd33, 24'd24, 24'd7, 24'd10, 24'd41, 24'd0, 24'd16, 24'd1, 24'd35, 24'd11, 24'd5, 24'd18, 24'd0, 24'd6, 24'd28, 24'd14, 24'd0, 24'd42, 24'd8, 24'd39, 24'd28, 24'd16, 24'd7, 24'd29, 24'd39, 24'd31, 24'd21, 24'd0, 24'd26, 24'd40, 
24'd16, 24'd14, 24'd38, 24'd32, 24'd9, 24'd3, 24'd18, 24'd15, 24'd1, 24'd19, 24'd19, 24'd44, 24'd4, 24'd16, 24'd15, 24'd24, 24'd19, 24'd40, 24'd13, 24'd18, 24'd10, 24'd12, 24'd16, 24'd20, 24'd30, 24'd22, 24'd10, 24'd12, 24'd19, 24'd9, 
24'd10, 24'd16, 24'd37, 24'd31, 24'd8, 24'd20, 24'd18, 24'd4, 24'd44, 24'd33, 24'd38, 24'd11, 24'd21, 24'd21, 24'd13, 24'd7, 24'd9, 24'd40, 24'd14, 24'd22, 24'd30, 24'd17, 24'd31, 24'd19, 24'd34, 24'd15, 24'd17, 24'd43, 24'd25, 24'd26, 
24'd13, 24'd25, 24'd3, 24'd25, 24'd13, 24'd24, 24'd9, 24'd11, 24'd33, 24'd5, 24'd5, 24'd12, 24'd8, 24'd3, 24'd4, 24'd28, 24'd20, 24'd20, 24'd41, 24'd28, 24'd25, 24'd18, 24'd30, 24'd36, 24'd3, 24'd23, 24'd32, 24'd31, 24'd23, 24'd19, 
24'd16, 24'd9, 24'd34, 24'd25, 24'd18, 24'd37, 24'd38, 24'd23, 24'd10, 24'd35, 24'd20, 24'd41, 24'd8, 24'd15, 24'd24, 24'd7, 24'd12, 24'd16, 24'd9, 24'd40, 24'd34, 24'd3, 24'd33, 24'd35, 24'd14, 24'd43, 24'd29, 24'd19, 24'd21, 24'd17
};
 	/*
 	integer i;
 	always @ (posedge advanceSignal_Processed) begin
 		for (i=0; i<`NFFT; i=i+1) begin
 			if (i==0) begin
 				//load most recent sample into buffer 0
 				SampleBuffers[i] <= SampleAmplitudeIn_Processed;
 			end
 			else begin
 				//Shift buffer contents down by 1 
 				SampleBuffers[i] <= SampleBuffers[i-1];
 			end
 		end	
 	end
 	*/
 	 	
 	//Shuffle input buffer
 	logic [`SFFT_OUTPUT_WIDTH -1:0] shuffledSamples [`NFFT -1:0];
 	
 	integer j;
 	
`ifdef SFFT_FIXEDPOINT_INPUTSCALING
 	parameter extensionBits = `SFFT_OUTPUT_WIDTH - `SFFT_FIXED_POINT_ACCURACY - `SFFT_INPUT_WIDTH - 1;
 	always @ (*) begin
 		for (j=0; j<`NFFT; j=j+1) begin
 			shuffledSamples[j] = {{extensionBits{SampleBuffers[shuffledInputIndexes[j]][`SFFT_INPUT_WIDTH -1]}}, SampleBuffers[shuffledInputIndexes[j]] << `SFFT_FIXED_POINT_ACCURACY};  //Left shift input by fixed-point accuracy, and sign extend to match output width
 		end
 	end
 	
`else
	parameter extensionBits = `SFFT_OUTPUT_WIDTH - `SFFT_INPUT_WIDTH - 1;
 	always @ (*) begin
 		for (j=0; j<`NFFT; j=j+1) begin
 			shuffledSamples[j] = {{extensionBits{SampleBuffers[shuffledInputIndexes[j]][`SFFT_INPUT_WIDTH -1]}}, SampleBuffers[shuffledInputIndexes[j]]};  //Sign extend to match output width
 		end
 	end
`endif
 	 	
 	//Notify pipeline of new input
 	reg newSampleReady;
	wire inputReceived;
	always @ (negedge clk) begin  //negedge to avoid race condition with advanceSignal_Processed
		if (reset) begin
			newSampleReady <= 0;
		end
		
		else if ((inputReceived==1) && (newSampleReady==1)) begin
			newSampleReady <= 0;
		end
		
		else if ((advanceSignal_Processed==1) && (newSampleReady==0) && (inputReceived==0)) begin
			newSampleReady <= 1;
		end
	end	
	
	
	//_______________________________
	//
	// Generate pipeline structure
	//_______________________________
	
	/*
	 * Copier instance
	 */
	
	//Input bus
	wire [`SFFT_OUTPUT_WIDTH -1:0] StageInImag [`NFFT -1:0];
 	assign StageInImag = '{default:0};
 	
 	//Output bus
 	wire [`nFFT -1:0] ramCopier_address_A;
 	wire ramCopier_writeEnable_A;
 	wire [`nFFT -1:0] ramCopier_address_B;
 	wire ramCopier_writeEnable_B;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramCopier_dataInReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramCopier_dataInImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramCopier_dataInReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramCopier_dataInImag_B;
 	
	//State control bus
	wire copying;
	assign inputReceived = copying;
	wire copier_outputReady;
	wire [1:0] copier_access_pointer;
	 	
	copyToRamStage copier(
		.clk(clk),
		.reset(reset),
		
		.StageInReal(shuffledSamples),
	 	.StageInImag(StageInImag),
	 	.copySignal(newSampleReady),
	 	
	 	.address_A(ramCopier_address_A),
	 	.writeEnable_A(ramCopier_writeEnable_A),
	 	.address_B(ramCopier_address_B),
	 	.writeEnable_B(ramCopier_writeEnable_B),
	 	.dataInReal_A(ramCopier_dataInReal_A),
	 	.dataInImag_A(ramCopier_dataInImag_A),
	 	.dataInReal_B(ramCopier_dataInReal_B),
	 	.dataInImag_B(ramCopier_dataInImag_B),
	 	
	 	.copying(copying),
	 	.outputReady(copier_outputReady),
	 	.ram_access_pointer(copier_access_pointer)
		);
	
	/*
	 * Stage instance
	 */
	
	//Input bus
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutReal_A;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutImag_A;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutReal_B;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutImag_B;
 	
 	//Output bus
	wire [`nFFT -1:0] ramStage_address_A;
 	wire ramStage_writeEnable_A;
 	wire [`nFFT -1:0] ramStage_address_B;
 	wire ramStage_writeEnable_B;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInImag_B;

	wire [1:0] pipelineStage_access_pointer;
	
	//State control bus
 	wire idle;
 	wire [`SFFT_STAGECOUNTER_WIDTH -1:0] virtualStageCounter;
 	
 	//ROM inputs
	reg [`nFFT -1:0] kValues_In [(`NFFT / 2) -1:0];
	reg [`nFFT -1:0] aIndexes_In [(`NFFT / 2) -1:0];
	reg [`nFFT -1:0] bIndexes_In [(`NFFT / 2) -1:0];
 	
 	//MUX for ROM inputs
	always @(*) begin
		kValues_In = kValues_Mapped[virtualStageCounter];
		aIndexes_In = aIndexes_Mapped[virtualStageCounter];
		bIndexes_In = bIndexes_Mapped[virtualStageCounter];
	end 
	
	pipelineStage Stage(
	 	.clk(clk),
	 	.reset(reset),
	 	
	 	.realCoefficents(realCoefficents),
		.imagCoefficents(imagCoefficents),
		.kValues(kValues_In),
		.aIndexes(aIndexes_In),
		.bIndexes(bIndexes_In),
	 	
	 	.ram_address_A(ramStage_address_A),
	 	.ram_writeEnable_A(ramStage_writeEnable_A),
	 	.ram_dataInReal_A(ramStage_dataInReal_A),
	 	.ram_dataInImag_A(ramStage_dataInImag_A),
	 	.ram_dataOutReal_A(ramStage_dataOutReal_A),
	 	.ram_dataOutImag_A(ramStage_dataOutImag_A),
	 	.ram_address_B(ramStage_address_B),
	 	.ram_writeEnable_B(ramStage_writeEnable_B),
	 	.ram_dataInReal_B(ramStage_dataInReal_B),
	 	.ram_dataInImag_B(ramStage_dataInImag_B),
	 	.ram_dataOutReal_B(ramStage_dataOutReal_B),
	 	.ram_dataOutImag_B(ramStage_dataOutImag_B),
	 	.ram_access_pointer(pipelineStage_access_pointer),
 	
	 	.idle(idle),
	 	.virtualStageCounter(virtualStageCounter),
	 	.inputReady(copier_outputReady),
	 	.outputReady(OutputValid)
	 	);	
	 	
	 
	/*
	 * Output access handling
	 */
	 	
	logic [1:0] nextOutput_access_pointer = 3;  //Points to the most recent output of the pipeline
	
	always @(posedge OutputValid) begin
		if (reset) begin
			nextOutput_access_pointer <= 3;
		end
		
		else begin
			nextOutput_access_pointer <= nextOutput_access_pointer + 1;
		end
	end
	
	logic [1:0] output_access_pointer;  //Points to the buffer we're currently reading from the software
	
	always @(posedge clk) begin
		if (OutputBeingRead == 0) begin
			output_access_pointer <= nextOutput_access_pointer; //Only update output_access_pointer when we are not reading from software
			outputReadError <= 0;
		end
		else begin
			if (output_access_pointer == copier_access_pointer) begin
				//The copy stage has caught up with where the driver is reading from. Set error flag high
				outputReadError <= 1;
			end
		end
	end
	
	
	//_______________________________
	//
	// Generate BRAM buffers
	//_______________________________
	
	/*
	 * Buffer 0
	 */
	logic ramBuffer0_readClock;
	
	//Input bus
	logic [`nFFT -1:0] ramBuffer0_address_A;
 	logic ramBuffer0_writeEnable_A;
 	logic [`nFFT -1:0] ramBuffer0_address_B;
 	logic ramBuffer0_writeEnable_B;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInReal_A;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInImag_A;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInReal_B;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInImag_B;
 	
 	//Output bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutImag_B;
/*	
`ifdef RUNNING_SIMULATION
	pipelineBuffer_RAM BRAM_0(
	 	.readClk(clk),
	 	.writeClk(clk),
	 	
	 	.read_address_A(ramBuffer0_address_A),
	 	.write_address_A(ramBuffer0_address_A),
	 	.writeEnable_A(ramBuffer0_writeEnable_A),
	 	.dataInReal_A(ramBuffer0_dataInReal_A),
	 	.dataInImag_A(ramBuffer0_dataInImag_A),
	 	.read_address_B(ramBuffer0_address_B),
	 	.write_address_B(ramBuffer0_address_B),
	 	.writeEnable_B(ramBuffer0_writeEnable_B),
	 	.dataInReal_B(ramBuffer0_dataInReal_B),
	 	.dataInImag_B(ramBuffer0_dataInImag_B),
	 	
	 	.dataOutReal_A(ramBuffer0_dataOutReal_A),
	 	.dataOutImag_A(ramBuffer0_dataOutImag_A),
	 	.dataOutReal_B(ramBuffer0_dataOutReal_B),
	 	.dataOutImag_B(ramBuffer0_dataOutImag_B)
	 	);
`else
*/	 
	 //Concatenate dataIn bus
	 wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataInConcatenated_A;
	 assign ramBuffer0_dataInConcatenated_A = {ramBuffer0_dataInReal_A, ramBuffer0_dataInImag_A};
	 
	 wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataInConcatenated_B;
	 assign ramBuffer0_dataInConcatenated_B = {ramBuffer0_dataInReal_B, ramBuffer0_dataInImag_B};

	//Concatenate dataOut bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataOutConcatenated_A;
	assign ramBuffer0_dataOutReal_A = ramBuffer0_dataOutConcatenated_A[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer0_dataOutImag_A = ramBuffer0_dataOutConcatenated_A[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataOutConcatenated_B;
	assign ramBuffer0_dataOutReal_B = ramBuffer0_dataOutConcatenated_B[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer0_dataOutImag_B = ramBuffer0_dataOutConcatenated_B[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];
 	
 	/*
	bramNewer BRAM_0(
		.address_a ( ramBuffer0_address_A ),
		.address_b ( ramBuffer0_address_B ),
		.clock ( clk ),
		.data_a ( ramBuffer0_dataInConcatenated_A ),
		.data_b ( ramBuffer0_dataInConcatenated_B ),
		.wren_a ( ramBuffer0_writeEnable_A ),
		.wren_b ( ramBuffer0_writeEnable_B ),
		.q_a ( ramBuffer0_dataOutConcatenated_A ),
		.q_b ( ramBuffer0_dataOutConcatenated_B )
		);
	*/
	
	myNewerBram BRAM_0(
		.clk(clk),
		.aa(ramBuffer0_address_A), 
		.ab(ramBuffer0_address_B),
		.da(ramBuffer0_dataInConcatenated_A), 
		.db(ramBuffer0_dataInConcatenated_B), 
		.wa(ramBuffer0_writeEnable_A), 
		.wb(ramBuffer0_writeEnable_B),
		.qa(ramBuffer0_dataOutConcatenated_A), 
		.qb(ramBuffer0_dataOutConcatenated_B)
		);
//`endif	
	
	//Buffer 0 write access control
	always @(*) begin		
		if (copier_access_pointer == 0) begin
			//Give access to copier stage
			ramBuffer0_address_A = ramCopier_address_A;
		 	ramBuffer0_writeEnable_A = ramCopier_writeEnable_A;
		 	ramBuffer0_dataInReal_A = ramCopier_dataInReal_A;
		 	ramBuffer0_dataInImag_A = ramCopier_dataInImag_A;
		 	
		 	ramBuffer0_address_B = ramCopier_address_B;
		 	ramBuffer0_writeEnable_B = ramCopier_writeEnable_B;
		 	ramBuffer0_dataInReal_B = ramCopier_dataInReal_B;
		 	ramBuffer0_dataInImag_B = ramCopier_dataInImag_B;
		 	
		 	ramBuffer0_readClock = ~clk;
		end
		
		else if (pipelineStage_access_pointer == 0) begin
			//Give access to pipeline stage
			ramBuffer0_address_A = ramStage_address_A;
		 	ramBuffer0_writeEnable_A = ramStage_writeEnable_A;
		 	ramBuffer0_dataInReal_A = ramStage_dataInReal_A;
		 	ramBuffer0_dataInImag_A = ramStage_dataInImag_A;
		 	
		 	ramBuffer0_address_B = ramStage_address_B;
		 	ramBuffer0_writeEnable_B = ramStage_writeEnable_B;
		 	ramBuffer0_dataInReal_B = ramStage_dataInReal_B;
		 	ramBuffer0_dataInImag_B = ramStage_dataInImag_B;
		 	
		 	ramBuffer0_readClock = ~clk;
		end
		
		else if (output_access_pointer == 0) begin
			//Give access to output port
			ramBuffer0_address_A = output_address;
		 	ramBuffer0_writeEnable_A = 0;
		 	ramBuffer0_dataInReal_A = 0;
		 	ramBuffer0_dataInImag_A = 0;
		 	
		 	ramBuffer0_address_B = 0;
		 	ramBuffer0_writeEnable_B = 0;
		 	ramBuffer0_dataInReal_B = 0;
		 	ramBuffer0_dataInImag_B = 0;
		 	
		 	ramBuffer0_readClock = clk;
		end
	end
	
	/*
	 * Buffer 1
	 */
	logic ramBuffer1_readClock;
	
	//Input bus
	logic [`nFFT -1:0] ramBuffer1_address_A;
 	logic ramBuffer1_writeEnable_A;
 	logic [`nFFT -1:0] ramBuffer1_address_B;
 	logic ramBuffer1_writeEnable_B;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataInReal_A;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataInImag_A;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataInReal_B;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataInImag_B;
 	
 	//Output bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer1_dataOutImag_B;
/*	
`ifdef RUNNING_SIMULATION
	pipelineBuffer_RAM BRAM_1(
	 	.readClk(clk),
	 	.writeClk(clk),
	 	
	 	.read_address_A(ramBuffer1_address_A),
	 	.write_address_A(ramBuffer1_address_A),
	 	.writeEnable_A(ramBuffer1_writeEnable_A),
	 	.dataInReal_A(ramBuffer1_dataInReal_A),
	 	.dataInImag_A(ramBuffer1_dataInImag_A),
	 	.read_address_B(ramBuffer1_address_B),
	 	.write_address_B(ramBuffer1_address_B),
	 	.writeEnable_B(ramBuffer1_writeEnable_B),
	 	.dataInReal_B(ramBuffer1_dataInReal_B),
	 	.dataInImag_B(ramBuffer1_dataInImag_B),
	 	
	 	.dataOutReal_A(ramBuffer1_dataOutReal_A),
	 	.dataOutImag_A(ramBuffer1_dataOutImag_A),
	 	.dataOutReal_B(ramBuffer1_dataOutReal_B),
	 	.dataOutImag_B(ramBuffer1_dataOutImag_B)
	 	);
`else
*/	 
	//Concatenate dataIn bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer1_dataInConcatenated_A;
	assign ramBuffer1_dataInConcatenated_A = {ramBuffer1_dataInReal_A, ramBuffer1_dataInImag_A};

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer1_dataInConcatenated_B;
	assign ramBuffer1_dataInConcatenated_B = {ramBuffer1_dataInReal_B, ramBuffer1_dataInImag_B};

	//Concatenate dataOut bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer1_dataOutConcatenated_A;
	assign ramBuffer1_dataOutReal_A =  ramBuffer1_dataOutConcatenated_A[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer1_dataOutImag_A =  ramBuffer1_dataOutConcatenated_A[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer1_dataOutConcatenated_B;
	assign ramBuffer1_dataOutReal_B =  ramBuffer1_dataOutConcatenated_B[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer1_dataOutImag_B =  ramBuffer1_dataOutConcatenated_B[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];
	/*
	bramNewer BRAM_1(
		.address_a ( ramBuffer1_address_A ),
		.address_b ( ramBuffer1_address_B ),
		.clock ( clk ),
		.data_a ( ramBuffer1_dataInConcatenated_A ),
		.data_b ( ramBuffer1_dataInConcatenated_B ),
		.wren_a ( ramBuffer1_writeEnable_A ),
		.wren_b ( ramBuffer1_writeEnable_B ),
		.q_a ( ramBuffer1_dataOutConcatenated_A ),
		.q_b ( ramBuffer1_dataOutConcatenated_B )
		);
	*/	
	myNewerBram BRAM_1(
		.clk(clk),
		.aa(ramBuffer1_address_A), 
		.ab(ramBuffer1_address_B),
		.da(ramBuffer1_dataInConcatenated_A), 
		.db(ramBuffer1_dataInConcatenated_B), 
		.wa(ramBuffer1_writeEnable_A), 
		.wb(ramBuffer1_writeEnable_B),
		.qa(ramBuffer1_dataOutConcatenated_A), 
		.qb(ramBuffer1_dataOutConcatenated_B)
		);
//`endif	
	
	//Buffer 1 write access control
	always @(*) begin		
		if (copier_access_pointer == 1) begin
			//Give access to copier stage
			ramBuffer1_address_A = ramCopier_address_A;
		 	ramBuffer1_writeEnable_A = ramCopier_writeEnable_A;
		 	ramBuffer1_dataInReal_A = ramCopier_dataInReal_A;
		 	ramBuffer1_dataInImag_A = ramCopier_dataInImag_A;
		 	
		 	ramBuffer1_address_B = ramCopier_address_B;
		 	ramBuffer1_writeEnable_B = ramCopier_writeEnable_B;
		 	ramBuffer1_dataInReal_B = ramCopier_dataInReal_B;
		 	ramBuffer1_dataInImag_B = ramCopier_dataInImag_B;
		 	
		 	ramBuffer1_readClock = ~clk;
		end
		
		else if (pipelineStage_access_pointer == 1) begin
			//Give access to pipeline stage
			ramBuffer1_address_A = ramStage_address_A;
		 	ramBuffer1_writeEnable_A = ramStage_writeEnable_A;
		 	ramBuffer1_dataInReal_A = ramStage_dataInReal_A;
		 	ramBuffer1_dataInImag_A = ramStage_dataInImag_A;
		 	
		 	ramBuffer1_address_B = ramStage_address_B;
		 	ramBuffer1_writeEnable_B = ramStage_writeEnable_B;
		 	ramBuffer1_dataInReal_B = ramStage_dataInReal_B;
		 	ramBuffer1_dataInImag_B = ramStage_dataInImag_B;
		 	
		 	ramBuffer1_readClock = ~clk;
		end
		
		else if (output_access_pointer == 1) begin
			//Give access to output port
			ramBuffer1_address_A = output_address;
		 	ramBuffer1_writeEnable_A = 0;
		 	ramBuffer1_dataInReal_A = 0;
		 	ramBuffer1_dataInImag_A = 0;
		 	
		 	ramBuffer1_address_B = 0;
		 	ramBuffer1_writeEnable_B = 0;
		 	ramBuffer1_dataInReal_B = 0;
		 	ramBuffer1_dataInImag_B = 0;
		 	
		 	ramBuffer1_readClock = clk;
		end
	end
	
	/*
	 * Buffer 2
	 */
	logic ramBuffer2_readClock;
	
	//Input bus
	logic [`nFFT -1:0] ramBuffer2_address_A;
 	logic ramBuffer2_writeEnable_A;
 	logic [`nFFT -1:0] ramBuffer2_address_B;
 	logic ramBuffer2_writeEnable_B;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataInReal_A;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataInImag_A;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataInReal_B;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataInImag_B;
 	
 	//Output bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer2_dataOutImag_B;
/*	
`ifdef RUNNING_SIMULATION
	pipelineBuffer_RAM BRAM_2(
	 	.readClk(clk),
	 	.writeClk(clk),
	 	
	 	.read_address_A(ramBuffer2_address_A),
	 	.write_address_A(ramBuffer2_address_A),
	 	.writeEnable_A(ramBuffer2_writeEnable_A),
	 	.dataInReal_A(ramBuffer2_dataInReal_A),
	 	.dataInImag_A(ramBuffer2_dataInImag_A),
	 	.read_address_B(ramBuffer2_address_B),
	 	.write_address_B(ramBuffer2_address_B),
	 	.writeEnable_B(ramBuffer2_writeEnable_B),
	 	.dataInReal_B(ramBuffer2_dataInReal_B),
	 	.dataInImag_B(ramBuffer2_dataInImag_B),
	 	
	 	.dataOutReal_A(ramBuffer2_dataOutReal_A),
	 	.dataOutImag_A(ramBuffer2_dataOutImag_A),
	 	.dataOutReal_B(ramBuffer2_dataOutReal_B),
	 	.dataOutImag_B(ramBuffer2_dataOutImag_B)
	 	);
`else
*/	
	//Concatenate dataIn bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer2_dataInConcatenated_A;
	assign ramBuffer2_dataInConcatenated_A = {ramBuffer2_dataInReal_A, ramBuffer2_dataInImag_A};

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer2_dataInConcatenated_B;
	assign ramBuffer2_dataInConcatenated_B = {ramBuffer2_dataInReal_B, ramBuffer2_dataInImag_B};


	//Concatenate dataOut bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer2_dataOutConcatenated_A;
	assign ramBuffer2_dataOutReal_A =  ramBuffer2_dataOutConcatenated_A[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer2_dataOutImag_A =  ramBuffer2_dataOutConcatenated_A[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer2_dataOutConcatenated_B;
	assign ramBuffer2_dataOutReal_B =  ramBuffer2_dataOutConcatenated_B[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer2_dataOutImag_B =  ramBuffer2_dataOutConcatenated_B[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];

	/*
	bramNewer BRAM_2(
		.address_a ( ramBuffer2_address_A ),
		.address_b ( ramBuffer2_address_B ),
		.clock ( clk ),
		.data_a ( ramBuffer2_dataInConcatenated_A ),
		.data_b ( ramBuffer2_dataInConcatenated_B ),
		.wren_a ( ramBuffer2_writeEnable_A ),
		.wren_b ( ramBuffer2_writeEnable_B ),
		.q_a ( ramBuffer2_dataOutConcatenated_A ),
		.q_b ( ramBuffer2_dataOutConcatenated_B )
		);
	*/	
	myNewerBram BRAM_2(
		.clk(clk),
		.aa(ramBuffer2_address_A), 
		.ab(ramBuffer2_address_B),
		.da(ramBuffer2_dataInConcatenated_A), 
		.db(ramBuffer2_dataInConcatenated_B), 
		.wa(ramBuffer2_writeEnable_A), 
		.wb(ramBuffer2_writeEnable_B),
		.qa(ramBuffer2_dataOutConcatenated_A), 
		.qb(ramBuffer2_dataOutConcatenated_B)
		);
//`endif	
	
	//Buffer 2 write access control
	always @(*) begin		
		if (copier_access_pointer == 2) begin
			//Give access to copier stage
			ramBuffer2_address_A = ramCopier_address_A;
		 	ramBuffer2_writeEnable_A = ramCopier_writeEnable_A;
		 	ramBuffer2_dataInReal_A = ramCopier_dataInReal_A;
		 	ramBuffer2_dataInImag_A = ramCopier_dataInImag_A;
		 	
		 	ramBuffer2_address_B = ramCopier_address_B;
		 	ramBuffer2_writeEnable_B = ramCopier_writeEnable_B;
		 	ramBuffer2_dataInReal_B = ramCopier_dataInReal_B;
		 	ramBuffer2_dataInImag_B = ramCopier_dataInImag_B;
		 	
		 	ramBuffer2_readClock = ~clk;
		end

		else if (pipelineStage_access_pointer == 2) begin
			//Give access to pipeline stage
			ramBuffer2_address_A = ramStage_address_A;
		 	ramBuffer2_writeEnable_A = ramStage_writeEnable_A;
		 	ramBuffer2_dataInReal_A = ramStage_dataInReal_A;
		 	ramBuffer2_dataInImag_A = ramStage_dataInImag_A;
		 	
		 	ramBuffer2_address_B = ramStage_address_B;
		 	ramBuffer2_writeEnable_B = ramStage_writeEnable_B;
		 	ramBuffer2_dataInReal_B = ramStage_dataInReal_B;
		 	ramBuffer2_dataInImag_B = ramStage_dataInImag_B;
		 	
		 	ramBuffer2_readClock = ~clk;
		end
		
		else if (output_access_pointer == 2) begin
			//Give access to output port
			ramBuffer2_address_A = output_address;
		 	ramBuffer2_writeEnable_A = 0;
		 	ramBuffer2_dataInReal_A = 0;
		 	ramBuffer2_dataInImag_A = 0;
		 	
		 	ramBuffer2_address_B = 0;
		 	ramBuffer2_writeEnable_B = 0;
		 	ramBuffer2_dataInReal_B = 0;
		 	ramBuffer2_dataInImag_B = 0;
		 	
		 	ramBuffer2_readClock = clk;
		end
	end
	
	/*
	 * Buffer 3
	 */
	logic ramBuffer3_readClock;
	
	//Input bus
	logic [`nFFT -1:0] ramBuffer3_address_A;
 	logic ramBuffer3_writeEnable_A;
 	logic [`nFFT -1:0] ramBuffer3_address_B;
 	logic ramBuffer3_writeEnable_B;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataInReal_A;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataInImag_A;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataInReal_B;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataInImag_B;
 	
 	//Output bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer3_dataOutImag_B;
/*	
`ifdef RUNNING_SIMULATION
	pipelineBuffer_RAM BRAM_3(
	 	.readClk(clk),
	 	.writeClk(clk),
	 	
	 	.read_address_A(ramBuffer3_address_A),
	 	.write_address_A(ramBuffer3_address_A),
	 	.writeEnable_A(ramBuffer3_writeEnable_A),
	 	.dataInReal_A(ramBuffer3_dataInReal_A),
	 	.dataInImag_A(ramBuffer3_dataInImag_A),
	 	.read_address_B(ramBuffer3_address_B),
	 	.write_address_B(ramBuffer3_address_B),
	 	.writeEnable_B(ramBuffer3_writeEnable_B),
	 	.dataInReal_B(ramBuffer3_dataInReal_B),
	 	.dataInImag_B(ramBuffer3_dataInImag_B),
	 	
	 	.dataOutReal_A(ramBuffer3_dataOutReal_A),
	 	.dataOutImag_A(ramBuffer3_dataOutImag_A),
	 	.dataOutReal_B(ramBuffer3_dataOutReal_B),
	 	.dataOutImag_B(ramBuffer3_dataOutImag_B)
	 	);
`else 
*/	
	//Concatenate dataIn bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer3_dataInConcatenated_A;
	assign ramBuffer3_dataInConcatenated_A = {ramBuffer3_dataInReal_A, ramBuffer3_dataInImag_A};

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer3_dataInConcatenated_B;
	assign ramBuffer3_dataInConcatenated_B = {ramBuffer3_dataInReal_B, ramBuffer3_dataInImag_B};

	//Concatenate dataOut bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer3_dataOutConcatenated_A;
	assign ramBuffer3_dataOutReal_A =  ramBuffer3_dataOutConcatenated_A[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer3_dataOutImag_A =  ramBuffer3_dataOutConcatenated_A[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer3_dataOutConcatenated_B;
	assign ramBuffer3_dataOutReal_B =  ramBuffer3_dataOutConcatenated_B[`SFFT_OUTPUT_WIDTH -1:0];
	assign ramBuffer3_dataOutImag_B =  ramBuffer3_dataOutConcatenated_B[(2*`SFFT_OUTPUT_WIDTH) -1 :`SFFT_OUTPUT_WIDTH ];

	/*
	bramNewer BRAM_3(
		.address_a ( ramBuffer3_address_A ),
		.address_b ( ramBuffer3_address_B ),
		.clock ( clk ),
		.data_a ( ramBuffer3_dataInConcatenated_A ),
		.data_b ( ramBuffer3_dataInConcatenated_B ),
		.wren_a ( ramBuffer3_writeEnable_A ),
		.wren_b ( ramBuffer3_writeEnable_B ),
		.q_a ( ramBuffer3_dataOutConcatenated_A ),
		.q_b ( ramBuffer3_dataOutConcatenated_B )
		);
	*/	
	myNewerBram BRAM_3(
		.clk(clk),
		.aa(ramBuffer3_address_A), 
		.ab(ramBuffer3_address_B),
		.da(ramBuffer3_dataInConcatenated_A), 
		.db(ramBuffer3_dataInConcatenated_B), 
		.wa(ramBuffer3_writeEnable_A), 
		.wb(ramBuffer3_writeEnable_B),
		.qa(ramBuffer3_dataOutConcatenated_A), 
		.qb(ramBuffer3_dataOutConcatenated_B)
		);
//`endif	
	
	//Buffer 3 write access control
	always @(*) begin		
		if (copier_access_pointer == 3) begin
			//Give access to copier stage
			ramBuffer3_address_A = ramCopier_address_A;
		 	ramBuffer3_writeEnable_A = ramCopier_writeEnable_A;
		 	ramBuffer3_dataInReal_A = ramCopier_dataInReal_A;
		 	ramBuffer3_dataInImag_A = ramCopier_dataInImag_A;
		 	
		 	ramBuffer3_address_B = ramCopier_address_B;
		 	ramBuffer3_writeEnable_B = ramCopier_writeEnable_B;
		 	ramBuffer3_dataInReal_B = ramCopier_dataInReal_B;
		 	ramBuffer3_dataInImag_B = ramCopier_dataInImag_B;
		 	
		 	ramBuffer3_readClock = ~clk;
		end
		
		else if (pipelineStage_access_pointer == 3) begin
			//Give access to pipeline stage
			ramBuffer3_address_A = ramStage_address_A;
		 	ramBuffer3_writeEnable_A = ramStage_writeEnable_A;
		 	ramBuffer3_dataInReal_A = ramStage_dataInReal_A;
		 	ramBuffer3_dataInImag_A = ramStage_dataInImag_A;
		 	
		 	ramBuffer3_address_B = ramStage_address_B;
		 	ramBuffer3_writeEnable_B = ramStage_writeEnable_B;
		 	ramBuffer3_dataInReal_B = ramStage_dataInReal_B;
		 	ramBuffer3_dataInImag_B = ramStage_dataInImag_B;
		 	
		 	ramBuffer3_readClock = ~clk;
		end
		
		else if (output_access_pointer == 3) begin
			//Give access to output port
			ramBuffer3_address_A = output_address;
		 	ramBuffer3_writeEnable_A = 0;
		 	ramBuffer3_dataInReal_A = 0;
		 	ramBuffer3_dataInImag_A = 0;
		 	
		 	ramBuffer3_address_B = 0;
		 	ramBuffer3_writeEnable_B = 0;
		 	ramBuffer3_dataInReal_B = 0;
		 	ramBuffer3_dataInImag_B = 0;
		 	
		 	ramBuffer3_readClock = clk;
		end
	end
	
	/*
	 * Read access control
	 */
	 
	//pipelineStage buffer read control
	always @(*) begin		
		if (pipelineStage_access_pointer == 0) begin
			//Read from buffer 0
			ramStage_dataOutReal_A = ramBuffer0_dataOutReal_A;
		 	ramStage_dataOutImag_A = ramBuffer0_dataOutImag_A;
		 
		 	ramStage_dataOutReal_B = ramBuffer0_dataOutReal_B;
		 	ramStage_dataOutImag_B = ramBuffer0_dataOutImag_B;
		end
		
		else if (pipelineStage_access_pointer == 1) begin
			//Read from buffer 1
			ramStage_dataOutReal_A = ramBuffer1_dataOutReal_A;
		 	ramStage_dataOutImag_A = ramBuffer1_dataOutImag_A;
		 
		 	ramStage_dataOutReal_B = ramBuffer1_dataOutReal_B;
		 	ramStage_dataOutImag_B = ramBuffer1_dataOutImag_B;
		end
		
		else if (pipelineStage_access_pointer == 2) begin
			//Read from buffer 2
			ramStage_dataOutReal_A = ramBuffer2_dataOutReal_A;
		 	ramStage_dataOutImag_A = ramBuffer2_dataOutImag_A;
		 
		 	ramStage_dataOutReal_B = ramBuffer2_dataOutReal_B;
		 	ramStage_dataOutImag_B = ramBuffer2_dataOutImag_B;
		end
		
		else if (pipelineStage_access_pointer == 3) begin
			//Read from buffer 3
			ramStage_dataOutReal_A = ramBuffer3_dataOutReal_A;
		 	ramStage_dataOutImag_A = ramBuffer3_dataOutImag_A;
		 
		 	ramStage_dataOutReal_B = ramBuffer3_dataOutReal_B;
		 	ramStage_dataOutImag_B = ramBuffer3_dataOutImag_B;
		end
	end
	
	//output buffer read control
	
	always @(*) begin		
		if (output_access_pointer == 0) begin
			//Read from buffer 0
			SFFT_OutReal = ramBuffer0_dataOutReal_A;
			Output_Why = ramBuffer0_dataOutReal_A;
			//Output_Why = {23'd0, ramBuffer0_address_A};
			//Output_Why = 32'd0;
		end
		
		else if (output_access_pointer == 1) begin
			//Read from buffer 1
			SFFT_OutReal = ramBuffer1_dataOutReal_A;
			Output_Why = ramBuffer1_dataOutReal_A;
			//Output_Why = {23'd0, ramBuffer1_address_A};
			//Output_Why = 32'd1;
		end
		
		else if (output_access_pointer == 2) begin
			//Read from buffer 2
			SFFT_OutReal = ramBuffer2_dataOutReal_A;
			Output_Why = ramBuffer2_dataOutReal_A;
			//Output_Why = {23'd0, ramBuffer2_address_A};
			//Output_Why = 32'd2;
		end
		
		else if (output_access_pointer == 3) begin
			//Read from buffer 3
			SFFT_OutReal = ramBuffer3_dataOutReal_A;
			Output_Why = ramBuffer3_dataOutReal_A;
			//Output_Why = {23'd0, ramBuffer3_address_A};
			//Output_Why = 32'd3;
		end
	end
	
	//_______________________________
	//
	// Simulation Probes
	//_______________________________
	
	wire [`nFFT -1:0] PROBE_shuffledInputIndexes [`NFFT -1:0];
	assign PROBE_shuffledInputIndexes = shuffledInputIndexes;
	
	wire [`SFFT_INPUT_WIDTH -1:0] PROBE_SampleBuffers [`NFFT -1:0];
	assign PROBE_SampleBuffers = SampleBuffers;
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_shuffledSamples [`NFFT -1:0];
	assign PROBE_shuffledSamples = shuffledSamples;
	
	wire PROBE_newSampleReady;
	assign PROBE_newSampleReady = newSampleReady;
	
`ifdef SFFT_DOWNSAMPLE_PRE
	wire [`SFFT_INPUT_WIDTH -1:0] PROBE_WindowBuffers [`SFFT_DOWNSAMPLE_PRE_FACTOR -1:0];
	assign PROBE_WindowBuffers = WindowBuffers;
`endif
	
	
 endmodule  //SFFT_Pipeline
 
 
 /*
  * Performs a single stage of the FFT butterfly calculation. Buffers inputs and outputs.
  */
 module pipelineStage(
 	input clk,
 	input reset,
 	
 	//Coefficient ROM
 	input logic [`SFFT_FIXED_POINT_ACCURACY:0] realCoefficents [(`NFFT / 2) -1:0],
	input logic [`SFFT_FIXED_POINT_ACCURACY:0] imagCoefficents [(`NFFT / 2) -1:0],
	//K values for stage ROM
	input logic [`nFFT -1:0] kValues [(`NFFT / 2) -1:0],
	//Butterfly Indexes
	input logic [`nFFT -1:0] aIndexes [(`NFFT / 2) -1:0],
	input logic [`nFFT -1:0] bIndexes [(`NFFT / 2) -1:0],
 	
 	//BRAM IO
 	output logic [`nFFT -1:0] ram_address_A,
 	output logic ram_writeEnable_A,
 	
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] ram_dataInReal_A,
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] ram_dataInImag_A,
 	
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] ram_dataOutReal_A,
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] ram_dataOutImag_A,
 	
 	output logic [`nFFT -1:0] ram_address_B,
 	output logic ram_writeEnable_B,
 	
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] ram_dataInReal_B,
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] ram_dataInImag_B,
 	
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] ram_dataOutReal_B,
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] ram_dataOutImag_B,
 	
 	output logic [1:0] ram_access_pointer,
 	
 	//State control
 	output reg idle,
 	output reg [`SFFT_STAGECOUNTER_WIDTH -1:0] virtualStageCounter,
 	input inputReady,
 	output reg outputReady
 	);
 	 	 	

 	//Counter for iterating through butterflies
 	parameter bCounterWidth = `nFFT - 1;
 	reg [bCounterWidth -1:0] btflyCounter;
 	
 	
 	//_______________________________
	//
	// Instantiate butterfly module
	//_______________________________
 	
 	//Inputs 	
 	reg [`SFFT_FIXED_POINT_ACCURACY:0] wInReal;
 	reg [`SFFT_FIXED_POINT_ACCURACY:0] wInImag;
 	
 	//Instantiate B
 	butterfly B(
		.aReal(ram_dataOutReal_A),
		.aImag(ram_dataOutImag_A),
		.bReal(ram_dataOutReal_B),
		.bImag(ram_dataOutImag_B),
		.wReal(wInReal),
		.wImag(wInImag),
	
		//Connect outputs directly to BRAM buffer outside of this module
		.AReal(ram_dataInReal_A),
		.AImag(ram_dataInImag_A),
		.BReal(ram_dataInReal_B),
		.BImag(ram_dataInImag_B)
		);
		
 	//MUX for selecting butterfly inputs
 	always @ (*) begin		
 		wInReal = realCoefficents[kValues[btflyCounter]];
 		wInImag = imagCoefficents[kValues[btflyCounter]];
 	end
 	
 	//Mux for BRAM buffer addresses
 	always @(*) begin
 		ram_address_A = aIndexes[btflyCounter];
 		ram_address_B = bIndexes[btflyCounter];
 	end
 	
 	//_______________________________
	//
	// Pipeline stage behaviour
	//_______________________________

 	parameter pipelineWidth = `NFFT /2;
 	integer i;
 	integer j;
 	
 	reg clockDivider = 0;
 	reg processing;
 	
 	assign ram_writeEnable_A = processing && clockDivider;
 	assign ram_writeEnable_B = processing && clockDivider;
 	
 	always @ (posedge clk) begin
 		if (reset) begin
 			idle <= 1;
 		
 			outputReady <= 0;
 			btflyCounter <= 0;
 			virtualStageCounter <= 0;
 			
 			processing <= 0;
 			clockDivider <= 0;
 			
 			ram_access_pointer <= 0;
 		end
 		
 		else begin
 			if ((idle==1) && (inputReady==1) && (outputReady==0)) begin
 				//Start processing
 				idle <= 0;
 					
 				processing <= 1;
 				btflyCounter <= 0;
 			end
 			
 			else if (idle==0) begin
 				//Write outputs
 					//NOTE: This operation is now taken care of by the BRAM buffer outside of this module
 				
 				//Toggle clockDivider
 				clockDivider <= ~clockDivider;
 				
 				
 				if (clockDivider) begin
 					//Increment counter
 					btflyCounter <= btflyCounter + 1;
 				
	 				if (btflyCounter == (pipelineWidth-1)) begin
	 					//We've reached the last butterfly calculation in this virtual stage
	 					
	 					if (virtualStageCounter == `nFFT-1) begin
	 						//We've reached the last stage
	 						outputReady <= 1;
	 						idle <= 1;

	 						virtualStageCounter <= 0;
	 						
	 						processing <= 0;
	 						
	 						//Select which BRAM buffer to use next
	 						ram_access_pointer <= ram_access_pointer + 1;
	 					end
	 					else begin 						
			 				//Move onto next virtual stage
	 						virtualStageCounter <= virtualStageCounter + 1;
	 					end
	 				end
	 			end
 			end
 			
 			else if (outputReady) begin
 				//Next stage has recieved our outputs. Set flag to 0
 				outputReady <= 0;
 			end
 		end
 	end
 	
 	//_______________________________
	//
	// Simulation Probes
	//_______________________________
	
	wire [bCounterWidth -1:0] PROBE_btflyCounter;
	assign PROBE_btflyCounter = btflyCounter;
	
	/*
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_StageReal [`NFFT -1:0];
	assign PROBE_StageReal = StageReal;
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_StageImag [`NFFT -1:0];
	assign PROBE_StageImag = StageImag;
	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_StageReal_Buffer [`NFFT -1:0];
	assign PROBE_StageReal_Buffer = StageReal_Buffer;
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_StageImag_Buffer [`NFFT -1:0];
	assign PROBE_StageImag_Buffer = StageImag_Buffer;
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_StageOutReal [`NFFT -1:0];
	assign PROBE_StageOutReal = StageOutReal;
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_StageOutImag [`NFFT -1:0];
	assign PROBE_StageOutImag = StageOutImag;
	
	//Coefficient ROM
 	wire [`SFFT_FIXED_POINT_ACCURACY:0] PROBE_realCoefficents [(`NFFT / 2) -1:0];
 	assign PROBE_realCoefficents = realCoefficents;
	wire [`SFFT_FIXED_POINT_ACCURACY:0] PROBE_imagCoefficents [(`NFFT / 2) -1:0];
	assign PROBE_imagCoefficents = imagCoefficents;
	//K values for stage ROM
	wire [`nFFT -1:0] PROBE_kValues [(`NFFT / 2) -1:0];
	assign PROBE_kValues = kValues;
	//Butterfly Indexes
	wire [`nFFT -1:0] PROBE_aIndexes [(`NFFT / 2) -1:0];
	assign PROBE_aIndexes = aIndexes;
	wire [`nFFT -1:0] PROBE_bIndexes [(`NFFT / 2) -1:0];

	assign PROBE_bIndexes = bIndexes;
	*/
	
 endmodule  //pipelineStage
 
 
 /*
  * Performs a single 2-radix FFT. Performed continuously and asynchrounously. Does not buffer input or output
  */
module butterfly(
	//Inputs
	input [`SFFT_OUTPUT_WIDTH -1:0] aReal,
	input [`SFFT_OUTPUT_WIDTH -1:0] aImag,
	
	input [`SFFT_OUTPUT_WIDTH -1:0] bReal,
	input [`SFFT_OUTPUT_WIDTH -1:0] bImag,
	
	input [`SFFT_FIXED_POINT_ACCURACY:0] wReal,
	input [`SFFT_FIXED_POINT_ACCURACY:0] wImag,
	
	//Outputs
	output reg [`SFFT_OUTPUT_WIDTH -1:0] AReal,
	output reg [`SFFT_OUTPUT_WIDTH -1:0] AImag,
	
	output reg [`SFFT_OUTPUT_WIDTH -1:0] BReal,
	output reg [`SFFT_OUTPUT_WIDTH -1:0] BImag
	);

	//Sign extend coefficient to match bit width
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] wReal_Extended;
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] wImag_Extended;
	
	parameter extensionBitsCoeff = `SFFT_OUTPUT_WIDTH -1;
	
	always @ (*) begin
	    	wReal_Extended = { {extensionBitsCoeff{wReal[`SFFT_FIXED_POINT_ACCURACY]}}, wReal};
	    	wImag_Extended = { {extensionBitsCoeff{wImag[`SFFT_FIXED_POINT_ACCURACY]}}, wImag};
	end
	
	//Increase a bitwidth. Multiply a by 2^FIXEDPOINT
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] aReal_Extended;
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] aImag_Extended;
	
	parameter extensionBitsA = `SFFT_FIXED_POINT_ACCURACY;
	
	always @ (*) begin
		//Leftshift to multiply
	    	aReal_Extended = {aReal, {extensionBitsA{1'b0}}};
	    	aImag_Extended = {aImag, {extensionBitsA{1'b0}}};
	end
	
	//Increase b bitwidth
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] bReal_Extended;
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] bImag_Extended;
	
	parameter extensionBitsB = `SFFT_FIXED_POINT_ACCURACY;
	
	always @ (*) begin
		//Sign extension
	    	bReal_Extended = { {extensionBitsB{bReal[`SFFT_OUTPUT_WIDTH -1]}}, bReal};
	    	bImag_Extended = { {extensionBitsB{bImag[`SFFT_OUTPUT_WIDTH -1]}}, bImag};
	end
	
	//Do butterfly calculation
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] AReal_Intermediate;
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] AImag_Intermediate;
	
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] BReal_Intermediate;
	reg [`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:0] BImag_Intermediate;
	
	always @ (*) begin
		//A = a + wb
		AReal_Intermediate = aReal_Extended + (wReal_Extended*bReal_Extended) - (wImag_Extended*bImag_Extended);
		AImag_Intermediate = aImag_Extended + (wReal_Extended*bImag_Extended) + (wImag_Extended*bReal_Extended);
		
		//B = a - wb
		BReal_Intermediate = aReal_Extended - (wReal_Extended*bReal_Extended) + (wImag_Extended*bImag_Extended);
		BImag_Intermediate = aImag_Extended - (wReal_Extended*bImag_Extended) - (wImag_Extended*bReal_Extended);
		
		//Decrease magnitude of outputs by 2^7
		AReal = AReal_Intermediate[`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:`SFFT_FIXED_POINT_ACCURACY];
		AImag = AImag_Intermediate[`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:`SFFT_FIXED_POINT_ACCURACY];
		
		BReal = BReal_Intermediate[`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:`SFFT_FIXED_POINT_ACCURACY];
		BImag = BImag_Intermediate[`SFFT_OUTPUT_WIDTH + `SFFT_FIXED_POINT_ACCURACY -1:`SFFT_FIXED_POINT_ACCURACY];
	end
endmodule  //butterfly


/*
 * Copies values from buffer array into a given BRAM module
 */
module copyToRamStage(
	input clk,
	input reset,
	
	//Buffer array in
	input logic [`SFFT_OUTPUT_WIDTH -1:0] StageInReal [`NFFT -1:0],
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] StageInImag [`NFFT -1:0],
 	input copySignal,
 	
 	//BRAM IO
 	output wire [`nFFT -1:0] address_A,
 	output logic writeEnable_A,
 	output wire [`nFFT -1:0] address_B,
 	output logic writeEnable_B,
 	
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataInReal_A,
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataInImag_A,
 	
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataInReal_B,
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataInImag_B,
 	
 	//State control
 	output reg copying,
 	output reg outputReady,
 	output logic [1:0] ram_access_pointer
	);


	reg [`nFFT -1:0] addressCounter = 0;
	
	assign address_A = addressCounter;
	assign address_B = addressCounter + 1;
	
	//Mux for dataIn values
	always @(*) begin
		dataInReal_A = StageInReal[address_A];
		dataInImag_A = StageInImag[address_A];
		
		dataInReal_B = StageInReal[address_B];
		dataInImag_B = StageInImag[address_B];
	end
	
	always @ (posedge clk) begin
		if (reset) begin
			addressCounter <= 0;
			copying <= 0;
			outputReady <= 0;
			
			writeEnable_A <= 0;
			writeEnable_B <= 0;
			
			ram_access_pointer <= 0;
		end
		
		else begin
			if ((copying == 0) && (copySignal == 1)) begin
				//start copying operation
				copying <= 1;
				
				addressCounter <= 0;
				writeEnable_A <= 1;
				writeEnable_B <= 1;
			end
			else if (copying) begin
				addressCounter <= addressCounter + 1;
				if (addressCounter == `NFFT-2) begin
					//We're done copying
					writeEnable_A <= 0;
					writeEnable_B <= 0;
					
					copying <= 0;
					outputReady <= 1;
					
					//Select which BRAM buffer to use next
					ram_access_pointer <= ram_access_pointer + 1;
				end
			end
			
			else if (outputReady) begin
				outputReady <= 0;
			end
		end
	
	end
		
endmodule

