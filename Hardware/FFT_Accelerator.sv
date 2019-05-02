// CSEE 4840 Lab 1
// By: Jose Rubianes & Tomin Perea-Chamblee & Eitan Kaplan


`include "./AudioCodecDrivers/audio_driver.sv"
`include "SfftPipeline.sv"
//`include "SfftPipeline_SingleStage.sv"
//`include "peaks.sv"
`include "peaksSequential.sv"


module FFT_Accelerator( 
		  input logic clk,
		  input logic reset,

		  input logic [3:0] 	KEY, // Pushbuttons; KEY[0] is rightmost

		  // 7-segment LED displays; HEX0 is rightmost
		  output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5,
		  
		  //Audio pin assignments
		  output logic FPGA_I2C_SCLK,
		  inout FPGA_I2C_SDAT,
		  output logic AUD_XCK,
		  input logic AUD_DACLRCK,
		  input logic AUD_ADCLRCK,
		  input logic AUD_BCLK,
		  input logic AUD_ADCDAT,
		  output logic AUD_DACDAT,
		  
		  //Driver IO ports
		  input logic [7:0] writedata,
		  input logic write,
		  input chipselect,
		  input logic [7:0] address,
		  output logic [7:0] readdata
		  );

	
	//Debounce button inputs 
	wire KEY3db, KEY2db, KEY1db, KEY0db;  //debounced buttons
	debouncer db(.clk(clk), .buttonsIn(KEY), .buttonsOut({KEY3db, KEY2db, KEY1db, KEY0db}));

	//Instantiate audio controller
	reg [23:0] dac_left_in;
	reg [23:0] dac_right_in;
	
	wire [23:0] adc_left_out;
	wire [23:0] adc_right_out;
	
	wire advance;
	
	reg [23:0] adc_out_buffer = 0;
	
	reg [24:0] counter = 0;  //downsample adance signal
	
	audio_driver aDriver(
	 	.CLOCK_50(clk), 
	 	.reset(reset), 
	 	.dac_left(dac_left_in), 
	 	.dac_right(dac_right_in), 
	 	.adc_left(adc_left_out), 
	 	.adc_right(adc_right_out), 
	 	.advance(advance), 
	 	.FPGA_I2C_SCLK(FPGA_I2C_SCLK), 
	 	.FPGA_I2C_SDAT(FPGA_I2C_SDAT), 
	 	.AUD_XCK(AUD_XCK), 
	 	.AUD_DACLRCK(AUD_DACLRCK), 
	 	.AUD_ADCLRCK(AUD_ADCLRCK), 
	 	.AUD_BCLK(AUD_BCLK), 
	 	.AUD_ADCDAT(AUD_ADCDAT), 
	 	.AUD_DACDAT(AUD_DACDAT)
	 	);
	 
		
	//Instantiate SFFT pipeline
	reg [23:0] audioInMono;  //Convert stereo input to mono
	always @ (*) begin
		audioInMono = adc_right_out + adc_left_out;
	end
	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out [`NFFT -1:0];
 	wire SfftOutputValid;
 
 	SFFT_Pipeline sfft(
	 	.clk(clk),
	 	.reset(reset),
	 	
	 	.SampleAmplitudeIn(audioInMono),
	 	.advanceSignal(advance),
	 	
	 	.SFFT_Out(SFFT_Out),
	 	.OutputValid(SfftOutputValid)
	 	);
	
	
	reg [`SFFT_OUTPUT_WIDTH -1:0] dummySample;
	reg [`nFFT -1:0] dummyCounterA;
	reg [`nFFT -1:0] dummyCounterB;
	always @ (posedge clk) begin
		dummyCounterA <= dummyCounterA + 1;
		dummyCounterB <= dummyCounterB + dummyCounterA;
		dummySample <= SFFT_Out[dummyCounterB];
	end
	
	 		 
	/*	
	//Instantiate Peak finder
	wire [`FINAL_AMPL_WIDTH -1:0] peakAmplitudesOut [`PEAKS -1:0];
	wire [`FREQ_WIDTH -1:0] peakFreqsOut[`PEAKS -1:0];
	wire [`TIME_COUNTER_WIDTH -1:0] peaksCounterOut;
		
	peaks peakFinder( 
		.clk(clk),
		.reset(reset),
		
		.valid_in(SfftOutputValid),
		.fft_in(SFFT_Out[`FREQS -1:0]),
		
		.amplitudes_out(peakAmplitudesOut),
		.freqs_out(peakFreqsOut),
		.counter_out(peaksCounterOut)
		);
	*/
	//Instantiate Peak finder
	reg [`FINAL_AMPL_WIDTH -1:0] peakAmplitudesOut [`PEAKS -1:0];
	reg [`FREQ_WIDTH -1:0] peakFreqsOut[`PEAKS -1:0];
	reg [`TIME_COUNTER_WIDTH -1:0] peaksCounterOut;
			
	//Instantiate hex decoders
	hex7seg h5( .a(adc_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(adc_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(adc_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(adc_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(dummySample[7:4]),.y(HEX1) ),
		h0( .a(dummySample[3:0]),.y(HEX0) );
		//h1( .a(adc_out_buffer[7:4]),.y(HEX1) ),
		//h0( .a(adc_out_buffer[3:0]),.y(HEX0) );

	
	//Determine when the driver is in the middle of pulling a sample
	reg sampleBeingTaken;
	parameter maxAddressPulled = 33;
	always @(posedge clk) begin
		if (address < maxAddressPulled) begin
			sampleBeingTaken <= 1;
		end
		else begin
			sampleBeingTaken <= 0;
		end
	end
	
	//Map peaks output onto readOutBus
	reg [7:0] readOutBus_buffer [255:0];
	always @(posedge clk) begin
		if (sampleBeingTaken == 0) begin
			//Counter -> address 0-3. Assuming 32 bit counter
			readOutBus_buffer[0] <= peaksCounterOut[`TIME_COUNTER_WIDTH -1:`TIME_COUNTER_WIDTH -8];
			readOutBus_buffer[1] <= peaksCounterOut[`TIME_COUNTER_WIDTH -9:`TIME_COUNTER_WIDTH -16];
			readOutBus_buffer[2] <= peaksCounterOut[`TIME_COUNTER_WIDTH -17:`TIME_COUNTER_WIDTH -24];
			readOutBus_buffer[3] <= peaksCounterOut[`TIME_COUNTER_WIDTH -25:`TIME_COUNTER_WIDTH -32];
			
			//Freqenies 0-6 -> address 4-9. Assuming 8 bit frequency
			readOutBus_buffer[4] <= peakFreqsOut[0];
			readOutBus_buffer[5] <= peakFreqsOut[1];
			readOutBus_buffer[6] <= peakFreqsOut[2];
			readOutBus_buffer[7] <= peakFreqsOut[3];
			readOutBus_buffer[8] <= peakFreqsOut[4];
			readOutBus_buffer[9] <= peakFreqsOut[5];
			
			//Amplitudes 0-6 -> address {10-13, 14-17, 18-21, 22-25, 26-29, 30-33}. Assuming 32 bit frequency amplitude
			readOutBus_buffer[10] <= peakAmplitudesOut[0][`FINAL_AMPL_WIDTH -1:`FINAL_AMPL_WIDTH -8];
			readOutBus_buffer[11] <= peakAmplitudesOut[0][`FINAL_AMPL_WIDTH -9:`FINAL_AMPL_WIDTH -16];
			readOutBus_buffer[12] <= peakAmplitudesOut[0][`FINAL_AMPL_WIDTH -17:`FINAL_AMPL_WIDTH -24];
			//readOutBus_buffer[13] <= peakAmplitudesOut[0][`FINAL_AMPL_WIDTH -25:`FINAL_AMPL_WIDTH -32];
			
			readOutBus_buffer[14] <= peakAmplitudesOut[1][`FINAL_AMPL_WIDTH -1:`FINAL_AMPL_WIDTH -8];
			readOutBus_buffer[15] <= peakAmplitudesOut[1][`FINAL_AMPL_WIDTH -9:`FINAL_AMPL_WIDTH -16];
			readOutBus_buffer[16] <= peakAmplitudesOut[1][`FINAL_AMPL_WIDTH -17:`FINAL_AMPL_WIDTH -24];
			//readOutBus_buffer[17] <= peakAmplitudesOut[1][`FINAL_AMPL_WIDTH -25:`FINAL_AMPL_WIDTH -32];
			
			readOutBus_buffer[18] <= peakAmplitudesOut[2][`FINAL_AMPL_WIDTH -1:`FINAL_AMPL_WIDTH -8];
			readOutBus_buffer[19] <= peakAmplitudesOut[2][`FINAL_AMPL_WIDTH -9:`FINAL_AMPL_WIDTH -16];
			readOutBus_buffer[20] <= peakAmplitudesOut[2][`FINAL_AMPL_WIDTH -17:`FINAL_AMPL_WIDTH -24];
			//readOutBus_buffer[21] <= peakAmplitudesOut[2][`FINAL_AMPL_WIDTH -25:`FINAL_AMPL_WIDTH -32];
			
			readOutBus_buffer[22] <= peakAmplitudesOut[3][`FINAL_AMPL_WIDTH -1:`FINAL_AMPL_WIDTH -8];
			readOutBus_buffer[23] <= peakAmplitudesOut[3][`FINAL_AMPL_WIDTH -9:`FINAL_AMPL_WIDTH -16];
			readOutBus_buffer[24] <= peakAmplitudesOut[3][`FINAL_AMPL_WIDTH -17:`FINAL_AMPL_WIDTH -24];
			//readOutBus_buffer[25] <= peakAmplitudesOut[3][`FINAL_AMPL_WIDTH -25:`FINAL_AMPL_WIDTH -32];
			
			readOutBus_buffer[26] <= peakAmplitudesOut[4][`FINAL_AMPL_WIDTH -1:`FINAL_AMPL_WIDTH -8];
			readOutBus_buffer[27] <= peakAmplitudesOut[4][`FINAL_AMPL_WIDTH -9:`FINAL_AMPL_WIDTH -16];
			readOutBus_buffer[28] <= peakAmplitudesOut[4][`FINAL_AMPL_WIDTH -17:`FINAL_AMPL_WIDTH -24];
			//readOutBus_buffer[29] <= peakAmplitudesOut[4][`FINAL_AMPL_WIDTH -25:`FINAL_AMPL_WIDTH -32];
			
			readOutBus_buffer[30] <= peakAmplitudesOut[5][`FINAL_AMPL_WIDTH -1:`FINAL_AMPL_WIDTH -8];
			readOutBus_buffer[31] <= peakAmplitudesOut[5][`FINAL_AMPL_WIDTH -9:`FINAL_AMPL_WIDTH -16];
			readOutBus_buffer[32] <= peakAmplitudesOut[5][`FINAL_AMPL_WIDTH -17:`FINAL_AMPL_WIDTH -24];
			//readOutBus_buffer[33] <= peakAmplitudesOut[5][`FINAL_AMPL_WIDTH -25:`FINAL_AMPL_WIDTH -32];
			
			
			//Populate last 8 bytes with fixed test values
			readOutBus_buffer[248] <= 8'd42;
			readOutBus_buffer[249] <= 8'd53;
			readOutBus_buffer[250] <= 8'd84;
			readOutBus_buffer[251] <= 8'd71;
			readOutBus_buffer[252] <= 8'd7;
			readOutBus_buffer[253] <= 8'd25;
			readOutBus_buffer[254] <= 8'd48;
			readOutBus_buffer[255] <= 8'd96;
		end
	end
	
	//Read handling
	always @(posedge clk) begin
		readdata <= readOutBus_buffer[address];
	end
		
	//Sample inputs
	always @(posedge advance) begin
		counter <= counter + 1;
		dac_left_in <= adc_left_out;
		dac_right_in <= adc_right_out;
	end
	
	always @(posedge counter[12]) begin
		adc_out_buffer <= adc_left_out;
	end
	
endmodule


//Seven segment hex decoder
module hex7seg(input logic [3:0] a,
		output logic [6:0] y);

	always @ (a) begin
		case(a)
			0 : y = 7'b100_0000;
			1 : y = 7'b111_1001;
			2 : y = 7'b010_0100;
			3 : y = 7'b011_0000;
			4 : y = 7'b001_1001;
			5 : y = 7'b001_0010;
			6 : y = 7'b000_0010;
			7 : y = 7'b111_1000;
			8 : y = 7'b000_0000;
			9 : y = 7'b001_1000; 
			10 : y = 7'b000_1000;  //a
			11 : y = 7'b000_0011;  //b
			12 : y = 7'b100_0110;  //c
			13 : y = 7'b010_0001;  //d
			14 : y = 7'b000_0110;  //e
			15 : y = 7'b000_1110;  //f
			default: y = 7'b011_1111;
		endcase
	end
endmodule


//Debouncer for push buttons
module debouncer(input clk, input [3:0] buttonsIn, output logic [3:0] buttonsOut);
	logic [20:0] timer = 21'b0;
	
	always_ff @(posedge clk) begin
		timer <= timer - 21'b1;
	end
	
	always_ff @(negedge clk) begin
		if (timer == 0)
			buttonsOut <= buttonsIn;
	end

endmodule


