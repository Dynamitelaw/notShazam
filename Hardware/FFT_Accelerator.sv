// CSEE 4840 Lab 1
// By: Jose Rubianes & Tomin Perea-Chamblee


`include "./AudioCodecDrivers/audio_driver.sv"
`include "peaks.sv" // TODO remove later -- just included here to make sure peaks.sv compiles.

module FFT_Accelerator( input logic		  CLOCK_50,

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
		  output logic AUD_DACDAT
		  );


	//Read in generated parameters into ROM
	reg [`nFFT -1:0] shuffledInputIndexes [`NFFT -1:0];
	
	reg [`nFFT -1:0] kValues [`nFFT*(`NFFT / 2) -1:0];
	
	reg [`nFFT -1:0] aIndexes [`nFFT*(`NFFT / 2) -1:0];
	reg [`nFFT -1:0] bIndexes [`nFFT*(`NFFT / 2) -1:0];
	
	reg [`SFFT_FLOATING_POINT_ACCURACY:0] realCoefficents [(`NFFT / 2) -1:0];
	reg [`SFFT_FLOATING_POINT_ACCURACY:0] imagCoefficents [(`NFFT / 2) -1:0];
	
	initial begin
		$readmemh("GeneratedParameters/InputShuffledIndexes.txt", shuffledInputIndexes, 0);
		
		$readmemh("GeneratedParameters/Ks.txt", kValues, 0);
		
		$readmemh("GeneratedParameters/aIndexes.txt", aIndexes, 0);
		$readmemh("GeneratedParameters/bIndexes.txt", bIndexes, 0);
		
		$readmemh("GeneratedParameters/realCoefficients.txt", realCoefficents, 0);
		$readmemh("GeneratedParameters/imaginaryCoefficients.txt", imagCoefficents, 0);
	end
	
	
	
	//Debounce button inputs 
	wire KEY3db, KEY2db, KEY1db, KEY0db;  //debounced buttons
	debouncer db(.clk(clk), .buttonsIn(KEY), .buttonsOut({KEY3db, KEY2db, KEY1db, KEY0db}));

	assign clk = CLOCK_50;

	//Instantiate audio controller
	reg [23:0] dac_left_in;
	reg [23:0] dac_right_in;
	
	wire [23:0] adc_left_out;
	wire [23:0] adc_right_out;
	
	wire reset = ~KEY[3];
	
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
	 			
	//Instantiate hex decoders
	hex7seg h5( .a(adc_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(adc_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(adc_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(adc_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(adc_out_buffer[7:4]),.y(HEX1) ),
		h0( .a(adc_out_buffer[3:0]),.y(HEX0) );

		
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


