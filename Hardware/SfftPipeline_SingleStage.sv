/*
 * This module takes in samples of amplitudes, and outputs the N point FFT
 */
 
 `include "global_variables.sv"
 
 
 /*
  * Top level SFFT pipeline module.
  *
  * Samples the input signal <SampleAmplitudeIn> at the rising edge of <advanceSignal>. Begins processing the FFT immediately.
  * Only outputs the real components of the FFT result. Will raise <OutputValid> high for 1 cycle when the output is finished.
  *
  * Max sampling frequency ~= CLK_FREQ / (log2(NFFT)*NFFT/2+2). Output indeterminate if exceeded.
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
 	
 	parameter pipelineDepth = 1;
 	
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
		//NOTE: These filepaths must be changed to their absolute paths if simulating with Vsim. Otherwise they should be relative to Hardware directory
		//NOTE: If simulating with Vsim, make sure to run the Matlab script GenerateRomFiles.m if you change any global variables
		
		$readmemh("GeneratedParameters/InputShuffledIndexes.txt", shuffledInputIndexes, 0);
		
		$readmemh("GeneratedParameters/Ks.txt", kValues, 0);
		
		$readmemh("GeneratedParameters/aIndexes.txt", aIndexes, 0);
		$readmemh("GeneratedParameters/bIndexes.txt", bIndexes, 0);
		
		$readmemh("GeneratedParameters/realCoefficients.txt", realCoefficents, 0);
		$readmemh("GeneratedParameters/imaginaryCoefficients.txt", imagCoefficents, 0);
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
 	wire advanceSignal_Intermediate;
 	wire advanceSignal_Processed;
 	
 	/*
 	 * Implement downsampling if specified
 	 */
 	 
 	//Pre downsampling
`ifdef SFFT_DOWNSAMPLE_PRE
	//Shift buffer to hold SFFT_DOWNSAMPLE_PRE_FACTOR most recent raw samples
	reg [`SFFT_INPUT_WIDTH -1:0] WindowBuffers [`SFFT_DOWNSAMPLE_PRE_FACTOR -1:0];
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
 	logic [`SFFT_INPUT_WIDTH + `nDOWNSAMPLE_PRE -1:0] movingSum;
 	always @(posedge advanceSignal) begin
 		movingSum = movingSum + SampleAmplitudeIn - WindowBuffers[`SFFT_DOWNSAMPLE_PRE_FACTOR -1];
 	end
 	
 	assign SampleAmplitudeIn_Processed = movingSum[`SFFT_INPUT_WIDTH + `nDOWNSAMPLE_PRE -1:`nDOWNSAMPLE_PRE];  //right shift by nDOWNSAMPLE_PRE to divide sum into average
 	
 	//Counter for input downsampling
 	reg [`nDOWNSAMPLE_PRE -1:0] downsamplePRECounter = 0;
 	always @ (posedge advanceSignal) begin
		downsamplePRECounter <= downsamplePRECounter + 1;
	end
	
	assign advanceSignal_Intermediate = (downsamplePRECounter == 0);
`else
	assign SampleAmplitudeIn_Processed = SampleAmplitudeIn;
	assign advanceSignal_Intermediate = advanceSignal; 
`endif

	//Post downsampling
`ifdef SFFT_DOWNSAMPLE_POST
	reg [`nDOWNSAMPLE_POST -1:0] downsamplePOSTCounter = 0;
	always @ (posedge advanceSignal_Intermediate) begin
		downsamplePOSTCounter <= downsamplePOSTCounter + 1;
	end
	
	assign advanceSignal_Processed = (downsamplePOSTCounter == 0);
`else
 	assign advanceSignal_Processed = advanceSignal_Intermediate;
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
 	parameter extensionBits = `SFFT_OUTPUT_WIDTH - `SFFT_FIXED_POINT_ACCURACY - `SFFT_INPUT_WIDTH - 1;
 	always @ (*) begin
 		for (j=0; j<`NFFT; j=j+1) begin
 			shuffledSamples[j] = {{extensionBits{SampleBuffers[shuffledInputIndexes[j]][`SFFT_INPUT_WIDTH -1]}}, SampleBuffers[shuffledInputIndexes[j]] << `SFFT_FIXED_POINT_ACCURACY};  //Left shift input by fixed-point accuracy, and sign extend to match output width
 		end
 	end	
 	 	
 	//Notify pipeline of new input
 	reg newSampleReady;
	wire inputReceived;
	always @ (posedge clk) begin
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
	
	
	//Input Bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] StageInImag [`NFFT -1:0];
 	assign StageInImag = '{default:0};
 	
 	//Output Bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] StageOutImag [`NFFT -1:0];
 	
 	//State control bus
 	wire idle;
 	assign inputReceived = ~idle;
 	wire [`SFFT_STAGECOUNTER_WIDTH -1:0] virtualStageCounter;
 	reg inputReady;
 	wire outputReady;
 	
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

	//Stage instance
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
	 	
	 	.StageOutReal(SFFT_Out),
	 	.StageOutImag(StageOutImag),
	 	
	 	.idle(idle),
	 	.virtualStageCounter(virtualStageCounter),
	 	.inputReady(newSampleReady),
	 	.outputReady(OutputValid)
	 	);		
	 	
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
 	
 	//Stage Results
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] StageOutReal [`NFFT -1:0],
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] StageOutImag [`NFFT -1:0],
 	
 	//State control
 	output reg idle,
 	output reg [`SFFT_STAGECOUNTER_WIDTH -1:0] virtualStageCounter,
 	input inputReady,
 	output reg outputReady
 	);
 	 	 	
 	
 	//Stage input buffers
 	logic [`SFFT_OUTPUT_WIDTH -1:0] StageInReal_Buffer [`NFFT -1:0];
 	logic [`SFFT_OUTPUT_WIDTH -1:0] StageInImag_Buffer [`NFFT -1:0];
 	 	
 	//Counter for iterating through butterflies
 	parameter bCounterWidth = `nFFT - 1;
 	reg [bCounterWidth -1:0] btflyCounter;
 	
 	
 	//_______________________________
	//
	// Instantiate butterfly module
	//_______________________________
 	
 	//Inputs
 	reg [`SFFT_OUTPUT_WIDTH -1:0] aInReal;
 	reg [`SFFT_OUTPUT_WIDTH -1:0] aInImag;
 	
 	reg [`SFFT_OUTPUT_WIDTH -1:0] bInReal;
 	reg [`SFFT_OUTPUT_WIDTH -1:0] bInImag;
 	
 	reg [`SFFT_FIXED_POINT_ACCURACY:0] wInReal;
 	reg [`SFFT_FIXED_POINT_ACCURACY:0] wInImag;
 	
 	//Ouputs
 	wire [`SFFT_OUTPUT_WIDTH -1:0] AOutReal;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] AOutImag;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] BOutReal;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] BOutImag;
 	
 	//Instantiate B
 	butterfly B(
		.aReal(aInReal),
		.aImag(aInImag),
		.bReal(bInReal),
		.bImag(bInImag),
		.wReal(wInReal),
		.wImag(wInImag),
	
		.AReal(AOutReal),
		.AImag(AOutImag),
		.BReal(BOutReal),
		.BImag(BOutImag)
		);
		
 	//MUX for selecting butterfly inputs
 	always @ (*) begin
 		aInReal = StageInReal_Buffer[aIndexes[btflyCounter]];
 		aInImag = StageInImag_Buffer[aIndexes[btflyCounter]];
 		
 		bInReal = StageInReal_Buffer[bIndexes[btflyCounter]];
 		bInImag = StageInImag_Buffer[bIndexes[btflyCounter]];
 		
 		wInReal = realCoefficents[kValues[btflyCounter]];
 		wInImag = imagCoefficents[kValues[btflyCounter]];
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
 			outputReady <= 0;
 			btflyCounter <= 0;
 			virtualStageCounter <= 0;
 			
 			StageInReal_Buffer <= '{default:0};
 			StageInImag_Buffer <= '{default:0};
 		end
 		
 		else begin
 			if ((idle==1) && (inputReady==1) && (outputReady==0)) begin
 				//Buffer input and start processing
 				idle <= 0;
 				for (i=0; i<`NFFT; i=i+1) begin
 					StageInReal_Buffer[i] <= StageInReal[i];
 					StageInImag_Buffer[i] <= StageInImag[i];
 				end
 			end
 			
 			else if (idle==0) begin
 				//Write A output
 				StageOutReal[aIndexes[btflyCounter]] <= AOutReal;
 				StageOutImag[aIndexes[btflyCounter]] <= AOutImag;
 				
 				//Write B output
 				StageOutReal[bIndexes[btflyCounter]] <= BOutReal;
 				StageOutImag[bIndexes[btflyCounter]] <= BOutImag;
 				
 				//Increment counter
 				btflyCounter <= btflyCounter + 1;
 				
 				if (btflyCounter == (pipelineWidth-1)) begin
 					//We've reached the last butterfly calculation in this virtual stage
 					
 					if (virtualStageCounter == `nFFT-1) begin
 						//We've reached the last stage
 						outputReady <= 1;
 						idle <= 1;
 						
 						virtualStageCounter <= 0;
 					end
 					else begin 						
 						//Shift outputs to next inputs
 						for (j=0; j<`NFFT; j=j+1) begin
		 					StageInReal_Buffer[j] <= StageOutReal[j];
		 					StageInImag_Buffer[j] <= StageOutImag[j];
		 				end
		 				
		 				//Move onto next virtual stage
 						virtualStageCounter <= virtualStageCounter + 1;
 					end
 				end
 			end
 			
 			else if (outputReady) begin
 				//Next stage has recieved out outputs. Set flag to 0
 				outputReady <= 0;
 			end
 		end
 	end
 	
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
