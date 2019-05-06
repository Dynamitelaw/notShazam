/*
 * This module takes in samples of amplitudes, and outputs the N point FFT
 *
 * NOTE: This version of the pipeline is behind the Single-stage version in terms of development.
 * Differences include:
 *    -BRAM implementation (currently none)
 *    -IO port differences
 */
 
 `include "global_variables.sv"
 
 
 /*
  * Top level SFFT pipeline module.
  *
  * Samples the input signal <SampleAmplitudeIn> at the rising edge of <advanceSignal>. Begins processing the FFT immediately.
  * Only outputs the real components of the FFT result. Will raise <OutputValid> high for 1 cycle when the output is finished.
  *
  * Max sampling frequency ~= (CLK_FREQ*DOWNSAMPLE_PRE_FACTOR*DOWNSAMPLE_POST_FACTOR) / (NFFT/2+1). Output indeterminate if exceeded.
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
 	
 	parameter pipelineDepth = `nFFT;
 	
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
	
	genvar s;
	genvar k;
	generate
		//Generate pipeline stages
		for (s=0; s<pipelineDepth; s=s+1)
		begin : Pipeline
			//Input Bus
		 	wire [`SFFT_OUTPUT_WIDTH -1:0] StageInReal [`NFFT -1:0];
		 	wire [`SFFT_OUTPUT_WIDTH -1:0] StageInImag [`NFFT -1:0];
		 	
		 	//Output Bus
		 	wire [`SFFT_OUTPUT_WIDTH -1:0] StageOutReal [`NFFT -1:0];
		 	wire [`SFFT_OUTPUT_WIDTH -1:0] StageOutImag [`NFFT -1:0];
		 	
		 	//Timing control bus
		 	wire inputReady;
		 	wire idle;
		 	wire nextStageIdle;
		 	wire outputReady;
 	
 			//Stage instance
			pipelineStage Stage(
			 	.clk(clk),
			 	.reset(reset),
			 	
			 	.StageInReal(StageInReal),
			 	.StageInImag(StageInImag),
			 	.realCoefficents(realCoefficents),
				.imagCoefficents(imagCoefficents),
				.kValues(kValues[(s+1)*(`NFFT / 2)-1 : s*(`NFFT / 2)]),  //Map kValues ROM vector to correct pipeline stage
				.aIndexes(aIndexes[(s+1)*(`NFFT / 2)-1 : s*(`NFFT / 2)]),  //Map aIndexes ROM vector to correct pipeline stage
				.bIndexes(bIndexes[(s+1)*(`NFFT / 2)-1 : s*(`NFFT / 2)]),  //Map bIndexes ROM vector to correct pipeline stage
			 	
			 	.StageOutReal(StageOutReal),
			 	.StageOutImag(StageOutImag),
			 	
			 	.inputReady(inputReady),
			 	.idle(idle),
			 	.nextStageIdle(nextStageIdle),
			 	.outputReady(outputReady)
			 	);
		end
		
		//Connect intra-pipeline buses
		for (s=1; s<pipelineDepth; s=s+1)
		begin : InternalBusConnections
			for (k=0; k<`NFFT; k=k+1) 
			begin : InternalBusConnections_Sub
				assign Pipeline[s].StageInReal[k] = Pipeline[s-1].StageOutReal[k];
				assign Pipeline[s].StageInImag[k] = Pipeline[s-1].StageOutImag[k];
			end
			
			assign Pipeline[s].inputReady = Pipeline[s-1].outputReady;
			assign Pipeline[s-1].nextStageIdle = Pipeline[s].idle;
		end
		
		
		//Conect pipeline input stage
		for (k=0; k<`NFFT; k=k+1) 
		begin : InputBusConnections
			assign Pipeline[0].StageInReal[k] = shuffledSamples[k];
		end
		assign Pipeline[0].StageInImag = '{default:0};  //No imaginary input components
		
		assign Pipeline[0].inputReady = newSampleReady;
		assign inputReceived = ~Pipeline[0].idle;
		
		//Connect pipeline outputs
		for (k=0; k<`NFFT; k=k+1) 
		begin : OutputBusConnections
			assign SFFT_Out[k] = Pipeline[pipelineDepth-1].StageOutReal[k];  //Only output real components
		end
		assign OutputValid = Pipeline[pipelineDepth-1].outputReady;
		
		assign Pipeline[pipelineDepth-1].nextStageIdle = 0;
		
	endgenerate
	
	
	//_______________________________
	//
	// Simulation Probes
	//_______________________________
	
	wire [`SFFT_INPUT_WIDTH -1:0] PROBE_SampleBuffers [`NFFT -1:0];
	assign PROBE_SampleBuffers = SampleBuffers;
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_shuffledSamples [`NFFT -1:0];
	assign PROBE_shuffledSamples = shuffledSamples;
	
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
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] StageOutReal [`NFFT -1:0],
 	output wire [`SFFT_OUTPUT_WIDTH -1:0] StageOutImag [`NFFT -1:0],
 	
 	//Handshake timing control
 	input inputReady,
 	output reg idle,
 	
 	input nextStageIdle,
 	output reg outputReady
 	);
 	 	
 	
 	//Stage input buffers
 	logic [`SFFT_OUTPUT_WIDTH -1:0] StageReal_Buffer [`NFFT -1:0];
 	logic [`SFFT_OUTPUT_WIDTH -1:0] StageImag_Buffer [`NFFT -1:0];
 	
 	assign StageOutReal = StageReal_Buffer;
 	assign StageOutImag = StageImag_Buffer;
 	
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
 		aInReal = StageReal_Buffer[aIndexes[btflyCounter]];
 		aInImag = StageImag_Buffer[aIndexes[btflyCounter]];
 		
 		bInReal = StageReal_Buffer[bIndexes[btflyCounter]];
 		bInImag = StageImag_Buffer[bIndexes[btflyCounter]];
 		
 		wInReal = realCoefficents[kValues[btflyCounter]];
 		wInImag = imagCoefficents[kValues[btflyCounter]];
 	end
 	
 	
 	//_______________________________
	//
	// Pipeline stage behaviour
	//_______________________________

 	parameter pipelineWidth = `NFFT /2;
 	integer i;
 	always @ (posedge clk) begin
 		if (reset) begin
 			outputReady <= 0;
 			idle <= 1;
 			btflyCounter <= 0;
 			
 			StageReal_Buffer <= '{default:0};
 			StageImag_Buffer <= '{default:0};
 		end
 		
 		else begin
 			if ((idle==1) && (inputReady==1) && (outputReady==0)) begin
 				//Next stage has recieved our old outputs, we're idle, and previous stage has new inputs. Buffer input and start processing
 				idle <= 0;
 				for (i=0; i<`NFFT; i=i+1) begin
 					StageReal_Buffer[i] <= StageInReal[i];
 					StageImag_Buffer[i] <= StageInImag[i];
 				end
 			end
 			
 			else if (idle==0) begin
 				//Write A output
 				StageReal_Buffer[aIndexes[btflyCounter]] <= AOutReal;
 				StageImag_Buffer[aIndexes[btflyCounter]] <= AOutImag;
 				
 				//Write B output
 				StageReal_Buffer[bIndexes[btflyCounter]] <= BOutReal;
 				StageImag_Buffer[bIndexes[btflyCounter]] <= BOutImag;
 				
 				//Increment counter
 				btflyCounter <= btflyCounter + 1;
 				
 				if (btflyCounter == (pipelineWidth-1)) begin
 					//We've reached the last butterfly calculation
 					outputReady <= 1;
 					idle <= 1;
 				end
 			end
 			
 			else if ((outputReady==1) && (nextStageIdle==0)) begin
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
