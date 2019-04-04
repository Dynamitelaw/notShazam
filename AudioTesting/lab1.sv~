// CSEE 4840 Lab 1
// By: Jose Rubianes & Tomin Perea-Chamblee


`include "./starterkit/audio_driver.sv"
`include "I2C.sv"


module lab1( input logic		  CLOCK_50,

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

	logic [3:0] a = 4'b0000;// Address
	logic [7:0] din, dout; // RAM data in and out
	logic we; // RAM write enable

	logic clk;
	assign clk = CLOCK_50;

	//Instantiate audio controller
	wire [23:0] dac_left_in;
	wire [23:0] dac_right_in;
	
	wire [23:0] adc_left_out;
	wire [23:0] adc_right_out;
	
	wire reset = ~KEY[3];
	
	wire advance;
	
	reg [23:0] adc_out_buffer = 0;
	
	reg [12:0] counter = 0;  //downsample adance signal
	
	audio_driver (
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
	 	
	//Instantiate I2C driver
	reg I2C_start;
	wire I2C_communicating;
	reg I2C_SlaveAddress;
	reg I2C_RegisterAddress;
	reg I2C_write;
	reg I2C_read;
	reg [7:0] I2C_dataSend;
	wire [7:0] I2C_dataRecieved;

	I2C_Driver i2c(
		.CLOCK_50(CLOCK_50),
		.reset(reset),
		//Inputs
		.start(I2C_start),
		.communicating(I2C_communicating),
	
		.SlaveAddress(I2C_SlaveAddress),
		.RegisterAddress(I2C_RegisterAddress),
		.write(I2C_write),
		.read(I2C_read),
		.dataSend(I2C_dataSend),
		.dataRecieved(I2C_dataRecieved),
	
		//Outputs
		.FPGA_I2C_SCLK(FPGA_I2C_SCLK),
		.FPGA_I2C_SDAT(FPGA_I2C_SDAT),
		);	
		
	//Instantiate hex decoders
	hex7seg h5( .a(adc_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(adc_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(adc_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(adc_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(adc_out_buffer[7:4]),.y(HEX1) ),
		h0( .a(adc_out_buffer[3:0]),.y(HEX0) );
		//h0( .a({3'b0, FPGA_I2C_SCLK}),.y(HEX0) );
		
	always @(posedge advance) begin
		counter <= counter + 1;
		dac_left_in <= adc_left_out;
		//dac_right_in <= adc_left_out;
		dac_right_in <= adc_right_out;
	end
	
	always @(posedge counter[12]) begin
		adc_out_buffer <= adc_left_out;
	end

	always @(posedge clk) begin
		if(~KEY[0]) begin
			//Decrease input gain
			I2C_SlaveAddress <= ;  //page 43 datasheet http://www.cs.columbia.edu/~sedwards/classes/2012/4840/Wolfson-WM8731-audio-CODEC.pdf
			I2C_RegisterAddress <= 0;
			I2C_write <= 1;
			I2C_read <= 0;
			I2C_dataSend <= {1, 0, 0, 5'b10000};
			
			I2C_start <= 0;
		end
		else if(~KEY[1]) begin
			//Increase input gain
			I2C_SlaveAddress <= ;
			I2C_RegisterAddress <= 0;
			I2C_write <= 1;
			I2C_read <= 0;
			I2C_dataSend <= {1, 0, 0, 5'b10000};
			
			I2C_start <= 0;
		end
		else if(~KEY[2]) begin
			I2C_start <= 1;
		end
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

