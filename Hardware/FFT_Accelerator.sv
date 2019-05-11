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
	
	//Determine when the driver is in the middle of pulling a sample
	logic [7:0] driverReading = 8'd0;
	always @(posedge clk) begin
		if (chipselect && write) begin
			driverReading <= writedata;
		end	
	end
	
	wire sampleBeingTaken;
	assign sampleBeingTaken = driverReading[0];
	
	//Instantiate SFFT pipeline
 	wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out;
 	wire SfftOutputValid;
 	wire outputReadError;
 	logic [`nFFT -1:0] output_address = 0;
 	//assign output_address = address[`nFFT +1:2];
 
 	SFFT_Pipeline sfft(
	 	.clk(clk),
	 	.reset(reset),
	 	
	 	.SampleAmplitudeIn(audioInMono),
	 	.advanceSignal(advance),
	 	
	 	//Output BRAM IO
	 	.OutputBeingRead(sampleBeingTaken),
 		.outputReadError(outputReadError),
 		.output_address(output_address),
 		.SFFT_OutReal(SFFT_OUT),
	 	.OutputValid(SfftOutputValid)
	 	);
	
	//Sample counter
	reg [`TIME_COUNTER_WIDTH -1:0] timeCounter = 0;
	always @(posedge SfftOutputValid) begin
		timeCounter <= timeCounter + 1;
	end
	
	// DEBUG CODE
	logic [31:0] ampl0_buff = 0;
	
	logic [`SFFT_OUTPUT_WIDTH -1:0] fml;
	//Instantiate hex decoders
	hex7seg h5( .a(SFFT_Out[15:12]),.y(HEX5) ), // left digit
		h4( .a(SFFT_Out[11:8]),.y(HEX4) ),
		h3( .a(SFFT_Out[7:4]),.y(HEX3) ),
		h2( .a(SFFT_Out[3:0]),.y(HEX2) ),
		h1( .a(readdata[7:4]),.y(HEX1) ),
		h0( .a(readdata[3:0]),.y(HEX0) );
	
	/*
	//Instantiate hex decoders
	hex7seg h5( .a(adc_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(adc_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(adc_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(adc_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(adc_out_buffer[7:4]),.y(HEX1) ),
		h0( .a(adc_out_buffer[3:0]),.y(HEX0) );
	*/
	
	//Map timer counter output
	parameter readOutSize = 2048;
	reg [7:0] timer_buffer [3:0];
	integer i;
	always @(posedge clk) begin
		if (sampleBeingTaken == 0) begin
			//NOTE: Each 32bit word is written in reverse byte order, due to endian-ness of software. Avoids need for ntohl conversion
			
			//Counter -> address 0-3. Assuming 32 bit counter
			timer_buffer[3] <= timeCounter[31:24];
			timer_buffer[2] <= timeCounter[23:16];
			timer_buffer[1] <= timeCounter[15:8];
			timer_buffer[0] <= timeCounter[7:0];
		end
	end
	
	
	//Read handling
	logic [15:0] address_buffer;
	always @(posedge clk) begin
		address_buffer <= address;
	end
	
	always @(*) begin
		if (address_buffer < `NFFT*2) begin
			//Convert input address into subset of SFFT_Out
			//NOTE: Each 32bit word is written in reverse byte order, due to endian-ness of software. Avoids need for ntohl conversion
			if (address_buffer % 4 == 0) begin
				readdata = SFFT_Out[7:0];
			end
			else if (address_buffer % 4 == 1) begin
				readdata = SFFT_Out[15:8];
			end
			else if (address_buffer % 4 == 2) begin
				readdata = SFFT_Out[23:16];
			end
			else if (address_buffer % 4 == 3) begin
				readdata = SFFT_Out[31:24];
			end
		end
		else if (address_buffer[15:2] == `NFFT/2) begin
			//Send the timer counter
			readdata = timer_buffer[address[1:0]];
		end
		else begin
			//Send the valid byte
			readdata = {7'b0, ~outputReadError};
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


