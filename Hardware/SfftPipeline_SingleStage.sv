/*
 * This module takes in samples of amplitudes, and outputs the N point FFT
 */
 
 `include "global_variables.sv"
 `include "bram.sv"
 
 
 /*
  * Top level SFFT pipeline module.
  *
  * Samples the input signal <SampleAmplitudeIn> at the rising edge of <advanceSignal>. Begins processing the FFT immediately.
  * Only outputs the real components of the FFT result. Will raise <OutputValid> high for 1 cycle when the output is finished.
  *
  * Max sampling frequency ~= (CLK_FREQ*DOWNSAMPLE_PRE_FACTOR) / (log2(NFFT)*NFFT/2+2). Output indeterminate if exceeded.
  */
 module SFFT_Pipeline(
 	input clk,
 	input reset,
 	
 	//Inputs
 	input [`SFFT_INPUT_WIDTH -1:0] SampleAmplitudeIn,
 	input advanceSignal,
 	
 	//Outputs
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out [`NFFT -1:0],
 	output logic OutputValid
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
 	
 	assign SampleAmplitudeIn_Processed = movingSum[`SFFT_INPUT_WIDTH + `nDOWNSAMPLE_PRE -1:`nDOWNSAMPLE_PRE];  //right shift by nDOWNSAMPLE_PRE to divide sum into average
 	
 	//Counter for input downsampling
 	reg [`nDOWNSAMPLE_PRE -1:0] downsamplePRECounter = 0;
 	always @ (posedge advanceSignal) begin
		downsamplePRECounter <= downsamplePRECounter + 1;
	end
	
	always @ (posedge clk) begin
		advanceSignal_Intermediate <= (downsamplePRECounter == 0) && advanceSignal;
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
		downsamplePOSTCounter <= downsamplePOSTCounter + 1;
	end
	
	always @ (posedge clk) begin
		advanceSignal_Processed <= (downsamplePOSTCounter == 0) && advanceSignal_Intermediate;
	end
`else
	always @(*) begin
 		advanceSignal_Processed = advanceSignal_Intermediate;
 	end
`endif
 	
 	
 	//Shift buffer to hold N most recent samples
 	reg [`SFFT_INPUT_WIDTH -1:0] SampleBuffers [`NFFT -1:0] = '{default:0};
 	
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
		
		else if ((advanceSignal_Processed==1) && (newSampleReady==0)) begin
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
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataOutImag_B;
 	
 	//Output bus
	wire [`nFFT -1:0] ramStage_address_A;
 	wire ramStage_writeEnable_A;
 	wire [`nFFT -1:0] ramStage_address_B;
 	wire ramStage_writeEnable_B;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramStage_dataInImag_B;

	//State control bus
 	wire idle;
 	assign inputReceived = ~idle;
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
	 	
	 	.StageInReal(shuffledSamples),
	 	.StageInImag(StageInImag),
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
	 	.ram_access_pointer(),
 	
	 	.idle(idle),
	 	.virtualStageCounter(virtualStageCounter),
	 	.inputReady(newSampleReady),
	 	.outputReady(OutputValid)
	 	);	
	 	
	/*
	 * BRAM buffer
	 */
	 
	//Input bus
	logic [`nFFT -1:0] ramBuffer_address_A;
 	logic ramBuffer_writeEnable_A;
 	logic [`nFFT -1:0] ramBuffer_address_B;
 	logic ramBuffer_writeEnable_B;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataInReal_A;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataInImag_A;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataInReal_B;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataInImag_B;
 	
 	//Output bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer_dataOutImag_B;
	
	assign ramStage_dataOutReal_A = ramBuffer_dataOutReal_A;
 	assign ramStage_dataOutImag_A = ramBuffer_dataOutImag_A;
 	
 	assign ramStage_dataOutReal_B = ramBuffer_dataOutReal_B;
 	assign ramStage_dataOutImag_B = ramBuffer_dataOutImag_B;
	
	pipelineBuffer_RAM BRAM(
	 	.clk(clk),
	 	
	 	.address_A(ramBuffer_address_A),
	 	.writeEnable_A(ramBuffer_writeEnable_A),
	 	.address_B(ramBuffer_address_B),
	 	.writeEnable_B(ramBuffer_writeEnable_B),
	 	.dataInReal_A(ramBuffer_dataInReal_A),
	 	.dataInImag_A(ramBuffer_dataInImag_A),
	 	.dataInReal_B(ramBuffer_dataInReal_B),
	 	.dataInImag_B(ramBuffer_dataInImag_B),
	 	
	 	.dataOutReal_A(ramBuffer_dataOutReal_A),
	 	.dataOutImag_A(ramBuffer_dataOutImag_A),
	 	.dataOutReal_B(ramBuffer_dataOutReal_B),
	 	.dataOutImag_B(ramBuffer_dataOutImag_B)
	 	);
	
	//Buffer access control
	always @(*) begin
		if (ramStage_writeEnable_A) begin
			//Give access to pipeline stage
			ramBuffer_address_A = ramStage_address_A;
		 	ramBuffer_writeEnable_A = ramStage_writeEnable_A;
		 	ramBuffer_dataInReal_A = ramStage_dataInReal_A;
		 	ramBuffer_dataInImag_A = ramStage_dataInImag_A;
		 	
		 	ramBuffer_address_B = ramStage_address_B;
		 	ramBuffer_writeEnable_B = ramStage_writeEnable_B;
		 	ramBuffer_dataInReal_B = ramStage_dataInReal_B;
		 	ramBuffer_dataInImag_B = ramStage_dataInImag_B;
		end
		
		else if (ramCopier_writeEnable_A) begin
			//Give access to copier stage
			ramBuffer_address_A = ramCopier_address_A;
		 	ramBuffer_writeEnable_A = ramCopier_writeEnable_A;
		 	ramBuffer_dataInReal_A = ramCopier_dataInReal_A;
		 	ramBuffer_dataInImag_A = ramCopier_dataInImag_A;
		 	
		 	ramBuffer_address_B = ramCopier_address_B;
		 	ramBuffer_writeEnable_B = ramCopier_writeEnable_B;
		 	ramBuffer_dataInReal_B = ramCopier_dataInReal_B;
		 	ramBuffer_dataInImag_B = ramCopier_dataInImag_B;
		end
	end
	
	
	//_______________________________
	//
	// Simulation Probes
	//_______________________________
	
	
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
 	
 	//Stage Inputs
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] StageInReal [`NFFT -1:0],
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] StageInImag [`NFFT -1:0],
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
 	
 	//Ouputs
	 	//*NOTE: Now connected directly to BRAM buffer outside this module
 	
 	//Instantiate B
 	butterfly B(
		.aReal(ram_dataOutReal_A),
		.aImag(ram_dataOutImag_A),
		.bReal(ram_dataOutReal_B),
		.bImag(ram_dataOutImag_B),
		.wReal(wInReal),
		.wImag(wInImag),
	
		.AReal(ram_dataInReal_A),
		.AImag(ram_dataInImag_A),
		.BReal(ram_dataOutReal_B),
		.BImag(ram_dataOutImag_B)
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
 	always @ (posedge clk) begin
 		if (reset) begin
 			idle <= 1;
 		
 			outputReady <= 0;
 			btflyCounter <= 0;
 			virtualStageCounter <= 0;
 			
 			ram_writeEnable_A <= 0;
 			ram_writeEnable_B <= 0;
 			
 			ram_access_pointer <= 0;
 		end
 		
 		else begin
 			if ((idle==1) && (inputReady==1) && (outputReady==0)) begin
 				//Start processing 				
 				ram_writeEnable_A <= 1;
 				ram_writeEnable_B <= 1;
 			end
 			
 			else if (idle==0) begin
 				//Write outputs
 					//NOTE: This operation is now taken care of by the BRAM buffer outside of this module
 				
 				//Increment counter
 				btflyCounter <= btflyCounter + 1;
 				
 				if (btflyCounter == (pipelineWidth-1)) begin
 					//We've reached the last butterfly calculation in this virtual stage
 					
 					if (virtualStageCounter == `nFFT-1) begin
 						//We've reached the last stage
 						outputReady <= 1;
 						idle <= 1;

 						virtualStageCounter <= 0;
 						
 						ram_writeEnable_A <= 0;
 						ram_writeEnable_B <= 0;
 						
 						//Increment BRAM access pointer
 						if (ram_access_pointer == 2) begin
 							ram_access_pointer <= 0;
 						end
 						else begin
 							ram_access_pointer <= ram_access_pointer + 1;
 						end
 					end
 					else begin 						
		 				//Move onto next virtual stage
 						virtualStageCounter <= virtualStageCounter + 1;
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
	wire [`nFFT -1:0] PROBE_bIndexes [(`NFFT / 2) -1:0];sim/:Sfft_Testbench:sfft:copier:address_A

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
	reg [`SFFT_OUTPUT_WIDTH -1:0] wReal_Extended;
	reg [`SFFT_OUTPUT_WIDTH -1:0] wImag_Extended;
	
	parameter extensionBits = `SFFT_OUTPUT_WIDTH - `SFFT_FIXED_POINT_ACCURACY -1;
	
	always @ (*) begin
	    	wReal_Extended = { {extensionBits{wReal[`SFFT_FIXED_POINT_ACCURACY]}}, wReal};
	    	wImag_Extended = { {extensionBits{wImag[`SFFT_FIXED_POINT_ACCURACY]}}, wImag};
	end
	
	//We need to divide our b inputs by 2^FixedPointAccuracy due to the multiplication of 2 fixed point numbers
	reg [`SFFT_OUTPUT_WIDTH -1:0] bReal_Adjusted;
	reg [`SFFT_OUTPUT_WIDTH -1:0] bImag_Adjusted;
	
	always @ (*) begin
		//Right shift with sign extension
	    	bReal_Adjusted = { {extensionBits{bReal[`SFFT_OUTPUT_WIDTH -1]}}, bReal[`SFFT_OUTPUT_WIDTH -1:`SFFT_FIXED_POINT_ACCURACY]};
	    	bImag_Adjusted = { {extensionBits{bImag[`SFFT_OUTPUT_WIDTH -1]}}, bImag[`SFFT_OUTPUT_WIDTH -1:`SFFT_FIXED_POINT_ACCURACY]};
	end
	
	//Do butterfly calculation
	always @ (*) begin
		//TODO It works perfectly with A and B flipped, and I have no idea how or why
		//A = a + wb
		BReal = aReal + (wReal_Extended*bReal_Adjusted) - (wImag_Extended*bImag_Adjusted);
		BImag = aImag + (wReal_Extended*bImag_Adjusted) + (wImag_Extended*bReal_Adjusted);
		
		//B = a - wb
		AReal = aReal - (wReal_Extended*bReal_Adjusted) + (wImag_Extended*bImag_Adjusted);
		AImag = aImag - (wReal_Extended*bImag_Adjusted) - (wImag_Extended*bReal_Adjusted);
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
					
					if (ram_access_pointer == 2) begin
						ram_access_pointer <= 0;
					end
					else begin
						ram_access_pointer <= ram_access_pointer + 1;
					end
				end
			end
			
			else if (outputReady) begin
				outputReady <= 0;
			end
		end
	
	end
		
endmodule
