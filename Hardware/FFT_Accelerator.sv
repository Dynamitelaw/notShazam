// CSEE 4840 Design Project
// By: Jose Rubianes & Tomin Perea-Chamblee & Eitan Kaplan


`include "./AudioCodecDrivers/audio_driver.sv"
//`include "SfftPipeline.sv"
`include "SfftPipeline_SingleStage.sv"
//`include "peaks.sv"
//`include "peaksSequential.sv"


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
		  input logic [15:0] address,
		  output logic [7:0] readdata
		  );

	
	/*
	//Debounce button inputs 
	wire KEY3db, KEY2db, KEY1db, KEY0db;  //debounced buttons
	debouncer db(.clk(clk), .buttonsIn(KEY), .buttonsOut({KEY3db, KEY2db, KEY1db, KEY0db}));
	*/
	
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
	 
	//Convert stereo input to mono	
	reg [23:0] audioInMono;  
	always @ (*) begin
		audioInMono = adc_right_out + adc_left_out;
	end
	
	//Instantiate SFFT pipeline
	wire [`nFFT -1:0] output_address;
	assign output_address = address[`nFFT -1:0];
 	wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out;
 	wire SfftOutputValid;
 
 	SFFT_Pipeline sfft(
	 	.clk(clk),
	 	.reset(reset),
	 	
	 	.SampleAmplitudeIn(audioInMono),
	 	.advanceSignal(advance),
	 	
	 	.output_address(output_address),
	 	.SFFT_OutReal(SFFT_Out),
	 	.OutputValid(SfftOutputValid)
	 	);
	
	//Sample counter
	reg [`TIME_COUNTER_WIDTH -1:0] timeCounter = 0;
	always @(posedge SfftOutputValid) begin
		timeCounter <= timeCounter + 1;
	end
	
	
	//Instantiate hex decoders
	hex7seg h5( .a(adc_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(adc_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(adc_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(adc_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(adc_out_buffer[7:4]),.y(HEX1) ),
		h0( .a(adc_out_buffer[3:0]),.y(HEX0) );

	
	//Determine when the driver is in the middle of pulling a sample
	wire sampleBeingTaken;
	assign sampleBeingTaken = chipselect;
	
	//Map peaks output onto readOutBus
	reg [7:0] readOutBus_buffer [1023:0];
	integer i;
	always @(posedge clk) begin
		if (sampleBeingTaken == 0) begin
			//NOTE: Each 32bit word is written in reverse byte order, due to endian-ness of software. Avoids need for ntohl conversion
			
			//Counter -> address 0-3. Assuming 32 bit counter
			readOutBus_buffer[3] <= timeCounter[31:24];
			readOutBus_buffer[2] <= timeCounter[23:16];
			readOutBus_buffer[1] <= timeCounter[15:8];
			readOutBus_buffer[0] <= timeCounter[7:0];
			
			//Amplitudes out. Assuming 32 bit frequency amplitude
			/*
			for (i=0; i< `NFFT; i=i+1) begin
				readOutBus_buffer[i*4+7] <= SFFT_Out[i][31:24];
				readOutBus_buffer[i*4+6] <= SFFT_Out[i][23:16];
				readOutBus_buffer[i*4+5] <= SFFT_Out[i][15:8];
				readOutBus_buffer[i*4+4] <= SFFT_Out[i][7:0];
			end			
			*/
			
			//Populate value 247 with input sample amplitude. Must be disabled if NFFT > 128
			if (advance) begin
				readOutBus_buffer[247*4+7] <= {8{audioInMono[23]}};
				readOutBus_buffer[247*4+6] <= audioInMono[23:16];
				readOutBus_buffer[247*4+5] <= audioInMono[15:8];
				readOutBus_buffer[247*4+4] <= audioInMono[7:0];
			end
			
			//Populate last 7 values with fixed test values. Must be disabled if NFFT > 128
			readOutBus_buffer[248*4+7] <= 8'b00000000;
			readOutBus_buffer[248*4+6] <= 8'b00000000;
			readOutBus_buffer[248*4+5] <= 8'b00000000;
			readOutBus_buffer[248*4+4] <= 8'b00000000;
			
			readOutBus_buffer[249*4+7] <= 8'b11111111;
			readOutBus_buffer[249*4+6] <= 8'b11111111;
			readOutBus_buffer[249*4+5] <= 8'b11111111;
			readOutBus_buffer[249*4+4] <= 8'b11111111;
			
			readOutBus_buffer[250*4+7] <= 8'b11111111;
			readOutBus_buffer[250*4+6] <= 8'b00000000;
			readOutBus_buffer[250*4+5] <= 8'b00000000;
			readOutBus_buffer[250*4+4] <= 8'b00000000;
			
			readOutBus_buffer[251*4+7] <= 8'b11111111;
			readOutBus_buffer[251*4+6] <= 8'b00000000;
			readOutBus_buffer[251*4+5] <= 8'b11111111;
			readOutBus_buffer[251*4+4] <= 8'b00000000;
			
			readOutBus_buffer[252*4+7] <= 8'b11110000;
			readOutBus_buffer[252*4+6] <= 8'b00000000;
			readOutBus_buffer[252*4+5] <= 8'b00000000;
			readOutBus_buffer[252*4+4] <= 8'b00000000;
			
			readOutBus_buffer[253*4+7] <= 8'b11010010;
			readOutBus_buffer[253*4+6] <= 8'b00000000;
			readOutBus_buffer[253*4+5] <= 8'b00000000;
			readOutBus_buffer[253*4+4] <= 8'b00000000;
			
			readOutBus_buffer[254*4+7] <= 8'h01;
			readOutBus_buffer[254*4+6] <= 8'h23;
			readOutBus_buffer[254*4+5] <= 8'h45;
			readOutBus_buffer[254*4+4] <= 8'h67;
		end
	end
	
	//Read handling
	always @(posedge clk) begin
		if (address < 1024) begin
			readdata <= readOutBus_buffer[address];
		end
		else begin
			readdata <= 0;
		end
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


