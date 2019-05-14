/*
 * This module takes in samples of amplitudes, and outputs the N point FFT
 */
 
`include "global_variables.sv"

`ifdef RUNNING_SIMULATION
	`include "bram.sv"
`else
	//`include "bramNew.v"
	`include "bramNewer.v"
	//`include "bramNewest.v"
`endif
 
 
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
 	
 	reg [`SFFT_INPUT_WIDTH -1:0] SampleBuffers [`NFFT -1:0] = '{24'd8388608, 
24'd9081295, 24'd8846848, 24'd7999065, 24'd7672669, 24'd8304529, 24'd9048924, 24'd8909512, 24'd8072890, 24'd7658843, 24'd8221557, 24'd9007861, 24'd8965320, 24'd8150872, 24'd7654624, 24'd8140784, 24'd8958646, 24'd9013534, 24'd8231983, 24'd7660067, 24'd8063273, 24'd8901926, 24'd9053522, 24'd8315156, 24'd7675102, 24'd7990046, 24'd8838449, 24'd9084757, 24'd8399297, 24'd7699529, 24'd7922066, 
24'd8769049, 24'd9106827, 24'd8483296, 24'd7733029, 24'd7860227, 24'd8694642, 24'd9119442, 24'd8566049, 24'd7775158, 24'd7805344, 24'd8616205, 24'd9122436, 24'd8646467, 24'd7825363, 24'd7758140, 24'd8534772, 24'd9115769, 24'd8723489, 24'd7882984, 24'd7719236, 24'd8451415, 24'd9099529, 24'd8796103, 24'd7947260, 24'd7689143, 24'd8367231, 24'd9073930, 24'd8863352, 24'd8017347, 24'd7668259, 
24'd8283329, 24'd9039309, 24'd8924352, 24'd8092322, 24'd7656858, 24'd8200812, 24'd8996122, 24'd8978298, 24'd8171197, 24'd7655091, 24'd8120768, 24'd8944938, 24'd9024482, 24'd8252934, 24'd7662980, 24'd8044250, 24'd8886429, 24'd9062294, 24'd8336457, 24'd7680421, 24'd7972265, 24'd8821367, 24'd9091238, 24'd8420666, 24'd7707185, 24'd7905761, 24'd8750607, 24'd9110931, 24'd8504454, 24'd7742921, 
24'd7845613, 24'd8675082, 24'd9121116, 24'd8586716, 24'd7787156, 24'd7792614, 24'd8595786, 24'd9121657, 24'd8666371, 24'd7839309, 24'd7747461, 24'd8513762, 24'd9112548, 24'd8742369, 24'd7898694, 24'd7710749, 24'd8430091, 24'd9093909, 24'd8813710, 24'd7964528, 24'd7682960, 24'd8345873, 24'd9065984, 24'd8879454, 24'd8035945, 24'd7664461, 24'd8262218, 24'd9029142, 24'd8938736, 24'd8112005, 
24'd7655495, 24'd8180227, 24'd8983868, 24'd8990777, 24'd8191706, 24'd7656180, 24'd8100979, 24'd8930757, 24'd9034890, 24'd8273999, 24'd7666507, 24'd8025518, 24'd8870509, 24'd9070495, 24'd8357801, 24'd7686341, 24'd7954836, 24'd8803917, 24'd9097123, 24'd8442009, 24'd7715419, 24'd7889866, 24'd8731858, 24'd9114423, 24'd8525513, 24'd7753360, 24'd7831460, 24'd8655280, 24'd9122169, 24'd8607215, 
24'd7799664, 24'd7780390, 24'd8575191, 24'd9120257, 24'd8686040, 24'd7853721, 24'd7737326, 24'd8492646, 24'd9108714, 24'd8760949, 24'd7914820, 24'd7702837, 24'd8408731, 24'd9087690, 24'd8830956, 24'd7982155, 24'd7677375, 24'd8324551, 24'd9057464, 24'd8895139, 24'd8054842, 24'd7661277, 24'd8241215, 24'd9018432, 24'd8952655, 24'd8131923, 24'd7654753, 24'd8159819, 24'd8971109, 24'd9002744, 
24'd8212382, 24'd7657891, 24'd8081434, 24'd8916117, 24'd9044749, 24'd8295162, 24'd7670648, 24'd8007094, 24'd8854181, 24'd9078116, 24'd8379172, 24'd7692856, 24'd7937776, 24'd8786116, 24'd9102406, 24'd8463306, 24'd7724225, 24'd7874393, 24'd8712817, 24'd9117299, 24'd8546456, 24'd7764339, 24'd7817780, 24'd8635251, 24'd9122599, 24'd8627529, 24'd7812672, 24'd7768682, 24'd8554437, 24'd9118237, 
24'd8705456, 24'd7868587, 24'd7727744, 24'd8471441, 24'd9104269, 24'd8779212, 24'd7931347, 24'd7695507, 24'd8387354, 24'd9080879, 24'd8847826, 24'd8000128, 24'd7672394, 24'd8303283, 24'd9048376, 24'd8910395, 24'd8074022, 24'd7658709, 24'd8220336, 24'd9007187, 24'd8966094, 24'd8152058, 24'd7654634, 24'd8139604, 24'd8957855, 24'd9014191, 24'd8233208, 24'd7660221, 24'd8062150, 24'd8901029, 
24'd9054052, 24'd8316404, 24'd7675397, 24'd7988994, 24'd8837458, 24'd9085153, 24'd8400550, 24'd7699962, 24'd7921098, 24'd8767977, 24'd9107084, 24'd8484539, 24'd7733593, 24'd7859358, 24'd8693502, 24'd9119557, 24'd8567266, 24'd7775847, 24'd7804584, 24'd8615013, 24'd9122407, 24'd8647640, 24'd7826168, 24'd7757499, 24'd8533543, 24'd9115597, 24'd8724604, 24'd7883893, 24'd7718722, 24'd8450166, 
24'd9099216, 24'd8797145, 24'd7948263, 24'd7688764, 24'd8365978, 24'd9073480, 24'd8864308, 24'd8018429, 24'd7668020, 24'd8282088, 24'd9038728, 24'd8925208, 24'd8093469, 24'd7656761, 24'd8199601, 24'd8995418, 24'd8979044, 24'd8172394, 24'd7655137, 24'd8119601, 24'd8944119, 24'd9025107, 24'd8254166, 24'd7663169, 24'd8043143, 24'd8885507, 24'd9062791, 24'd8337707, 24'd7680752, 24'd7971233, 
24'd8820353, 24'd9091599, 24'd8421919, 24'd7707652, 24'd7904817, 24'd8749516, 24'd9111153, 24'd8505692, 24'd7743518, 24'd7844771, 24'd8673928, 24'd9121195, 24'd8587923, 24'd7787875, 24'd7791883, 24'd8594583, 24'd9121592, 24'd8667531, 24'd7840142, 24'd7746852, 24'd8512527, 24'd9112340, 24'd8743467, 24'd7899628, 24'd7710269, 24'd8428839, 24'd9093561, 24'd8814731, 24'd7965552, 24'd7682616, 
24'd8344622, 24'd9065501, 24'd8880385, 24'd8037045, 24'd7664257, 24'd8260983, 24'd9028529, 24'd8939566, 24'd8113166, 24'd7655434, 24'd8179025, 24'd8983134, 24'd8991493, 24'd8192914, 24'd7656263, 24'd8099826, 24'd8929911, 24'd9035483, 24'd8275237, 24'd7666733, 24'd8024429, 24'd8869563, 24'd9070957, 24'd8359054, 24'd7686706, 24'd7953826, 24'd8802883, 24'd9097449, 24'd8443259, 24'd7715920, 
24'd7888947, 24'd8730749, 24'd9114609, 24'd8526745, 24'd7753989, 24'd7830645, 24'd8654111, 24'd9122211, 24'd8608412, 24'd7800413, 24'd7779689, 24'd8573978, 24'd9120156, 24'd8687185, 24'd7854580, 24'd7736749, 24'd8491404, 24'd9108470, 24'd8762028, 24'd7915778, 24'd7702391, 24'd8407478, 24'd9087307, 24'd8831955, 24'd7983200, 24'd7677066, 24'd8323302, 24'd9056947, 24'd8896046, 24'd8055959, 
24'd7661109, 24'd8239987, 24'd9017787, 24'd8953456, 24'd8133097, 24'd7654729, 24'd8158628, 24'd8970345, 24'd9003430, 24'd8213599, 24'd7658010, 24'd8080296, 24'd8915245, 24'd9045310, 24'd8296405, 24'd7670909, 24'd8006024, 24'd8853211, 24'd9078545, 24'd8380425, 24'd7693257, 24'd7936788, 24'd8785061, 24'd9102697, 24'd8464553, 24'd7724758, 24'd7873500, 24'd8711692, 24'd9117449, 24'd8547680, 
24'd7764999, 24'd7816993, 24'd8634070, 24'd9122605, 24'd8628714, 24'd7813450, 24'd7768011, 24'd8553216, 24'd9118099, 24'd8706587, 24'd7869472, 24'd7727200, 24'd8470195, 24'd9103989, 24'd8780273, 24'd7932328, 24'd7695095, 24'd8386100, 24'd9080461, 24'd8848804, 24'd8001192, 24'd7672120, 24'd8302038, 24'd9047826, 24'd8911276, 24'd8075155, 24'd7658578, 24'd8219116, 24'd9006512, 24'd8966867, 
24'd8153245, 24'd7654646, 24'd8138425, 24'd8957063, 24'd9014846, 24'd8234433, 24'd7660377, 24'd8061028, 24'd8900131, 24'd9054580, 24'd8317651, 24'd7675694, 24'd7987943, 24'd8836465, 24'd9085548, 24'd8401804, 24'd7700397, 24'd7920133, 24'd8766903, 24'd9107340, 24'd8485782, 24'd7734160, 24'd7858490, 24'd8692361, 24'd9119670, 24'd8568481, 24'd7776538, 24'd7803826, 24'd8613820, 24'd9122377, 
24'd8648812, 24'd7826974, 24'd7756860, 24'd8532314, 24'd9115423, 24'd8725718, 24'd7884804, 24'd7718211, 24'd8448917, 24'd9098901, 24'd8798186, 24'd7949266, 24'd7688388, 24'd8364725, 24'd9073028, 24'd8865262, 24'd8019512, 24'd7667782, 24'd8280848, 24'd9038146, 24'd8926062, 24'd8094617, 24'd7656666, 24'd8198390, 24'd8994712, 24'd8979788, 24'd8173592, 24'd7655186, 24'd8118435, 24'd8943299, 
24'd9025730};
 	
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
`endif	
	
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
`endif	
	
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
`endif	
	
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
`endif	
	
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
		//A = a + wb
		AReal = aReal + (wReal_Extended*bReal_Adjusted) - (wImag_Extended*bImag_Adjusted);
		AImag = aImag + (wReal_Extended*bImag_Adjusted) + (wImag_Extended*bReal_Adjusted);
		
		//B = a - wb
		BReal = aReal - (wReal_Extended*bReal_Adjusted) + (wImag_Extended*bImag_Adjusted);
		BImag = aImag - (wReal_Extended*bImag_Adjusted) - (wImag_Extended*bReal_Adjusted);
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

