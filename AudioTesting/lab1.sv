// CSEE 4840 Lab 1: Display and modify the contents of a memory
//
// Spring 2019
//
// By: Jose Rubianes & Varun Varahabhotla
// Uni: jer2201 & vv2282

`include "./starterkit/xck_generator.v"
`include "./starterkit/xck_generator/xck_generator_0002.v"
`include "./starterkit/Altera_UP_Audio_Bit_Counter.v"
`include "./starterkit/Altera_UP_Audio_In_Deserializer.v"
`include "./starterkit/Altera_UP_Audio_Out_Serializer.v"
`include "./starterkit/Altera_UP_Clock_Edge.v"
`include "./starterkit/Altera_UP_I2C.v"
`include "./starterkit/Altera_UP_I2C_AV_Auto_Initialize.v"
`include "./starterkit/Altera_UP_I2C_DC_Auto_Initialize.v"
`include "./starterkit/Altera_UP_I2C_LCM_Auto_Initialize.v"
`include "./starterkit/Altera_UP_Slow_Clock_Generator.v"
`include "./starterkit/Altera_UP_SYNC_FIFO.v"
`include "./starterkit/audio_and_video_config.v"
`include "./starterkit/audio_codec.v"
`include "./starterkit/audio_driver.sv"


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
	wire [23:0] dac_left_out;
	wire reset = ~KEY[3];
	wire advance;
	
	reg [23:0] dac_out_buffer = 0;
	
	//reg downsampledAdvance = 0;
	reg [16:0] counter = 0;
	
	 audio_driver (
	 	.CLOCK_50(clk), 
	 	.reset(reset), 
	 	.dac_left(), 
	 	.dac_right(), 
	 	.adc_left(dac_left_out), 
	 	.adc_right(), 
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
	hex7seg h5( .a(dac_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(dac_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(dac_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(dac_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(dac_out_buffer[7:4]),.y(HEX1) ),
		h0( .a(dac_out_buffer[3:0]),.y(HEX0) );
		
	always @(posedge advance) begin
		counter <= counter + 1;
		//dac_out_buffer <= dac_left_out;
		//dac_out_buffer <= dac_out_buffer + 1;
	end
	
	always @(posedge counter[16]) begin
		dac_out_buffer <= dac_left_out;
	
	end

endmodule

//Controller module
module controller(input logic clk,
		  input logic [3:0] KEY,
		  input logic [7:0] dout,
		  output logic [3:0] a,
		  output logic [7:0] din,
		  output logic we);


	//Debounce button inputs 
	wire KEY3db, KEY2db, KEY1db, KEY0db;  //debounced buttons
	debouncer db(.clk(clk), .buttonsIn(KEY), .buttonsOut({KEY3db, KEY2db, KEY1db, KEY0db}));
	
	
	//Signal for when an address has been changed
	reg addressButtonPressed;	
	always @(posedge clk) begin
		addressButtonPressed <= !KEY3db | !KEY2db;
	end
	
	//Incriment or decriment address value
	always_ff @(posedge addressButtonPressed) begin
		if (KEY2db && !KEY3db) begin
			a <= a + 4'b1;
		end
		else if (!KEY2db && KEY3db) begin
			a <= a - 4'b1;	
		end		
	end
	
	
	//Signal for when an data should be changed
	reg dataButtonPressed;
	always @(posedge clk) begin
		dataButtonPressed = !KEY1db | !KEY0db;
	end
	
	//Incriment or decriment data value
	assign we = dataButtonPressed;
	always_ff @(posedge dataButtonPressed) begin  
		if (KEY0db && !KEY1db) begin
			din <= dout + 8'b1;
		end
		else if (!KEY0db && KEY1db) begin
			din <= dout - 8'b1;	
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

// 16 X 8 synchronous RAM with old data read-during-write behavior
module memory(input logic clk,
		input logic [3:0]  a,
		input logic [7:0]  din,
		input logic we,
		output logic [7:0] dout);

	logic [7:0] 			 mem [15:0];

	always_ff @(posedge clk) begin
		if (we) mem[a] <= din;
		dout <= mem[a];
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

/*
// CSEE 4840 Lab 1: Display and modify the contents of a memory
//
// Spring 2019
//
// By: Jose Rubianes & Varun Varahabhotla
// Uni: jer2201 & vv2282


module lab1( input logic		  CLOCK_50,

		  input logic [3:0] 	KEY, // Pushbuttons; KEY[0] is rightmost

		  // 7-segment LED displays; HEX0 is rightmost
		  output logic [6:0] HEX0, HEX1, HEX2, HEX3, HEX4, HEX5
		  );

	logic [3:0] a = 4'b0000;// Address
	logic [7:0] din, dout; // RAM data in and out
	logic we; // RAM write enable

	logic clk;
	assign clk = CLOCK_50;

	
	//Instantiate hex decoders
	hex7seg h0( .a(a),.y(HEX5) ), // rightmost digit
		h1( .a(dout[7:4]), .y(HEX3) ), // left middle
		h2( .a(dout[3:0]), .y(HEX2) ); // right middle
			  
	//Instantiate controller module
	controller c(.clk(clk),
		.KEY(KEY),
		.dout(dout),
		.a(a),
		.din(din),
		.we(we));

	//Instantiate memory module
	memory m( .clk(clk),
		.a(a),
		.din(din),
		.we(we),
		.dout(dout));

	//Leave the rest of the displays blank
	assign HEX4 = 7'b111_1111;
	assign HEX1 = 7'b111_1111;
	assign HEX0 = 7'b111_1101;

endmodule

//Controller module
module controller(input logic clk,
		  input logic [3:0] KEY,
		  input logic [7:0] dout,
		  output logic [3:0] a,
		  output logic [7:0] din,
		  output logic we);


	//Debounce button inputs 
	wire KEY3db, KEY2db, KEY1db, KEY0db;  //debounced buttons
	debouncer db(.clk(clk), .buttonsIn(KEY), .buttonsOut({KEY3db, KEY2db, KEY1db, KEY0db}));
	
	
	//Signal for when an address has been changed
	reg addressButtonPressed;	
	always @(posedge clk) begin
		addressButtonPressed <= !KEY3db | !KEY2db;
	end
	
	//Incriment or decriment address value
	always_ff @(posedge addressButtonPressed) begin
		if (KEY2db && !KEY3db) begin
			a <= a + 4'b1;
		end
		else if (!KEY2db && KEY3db) begin
			a <= a - 4'b1;	
		end		
	end
	
	
	//Signal for when an data should be changed
	reg dataButtonPressed;
	always @(posedge clk) begin
		dataButtonPressed = !KEY1db | !KEY0db;
	end
	
	//Incriment or decriment data value
	assign we = dataButtonPressed;
	always_ff @(posedge dataButtonPressed) begin  
		if (KEY0db && !KEY1db) begin
			din <= dout + 8'b1;
		end
		else if (!KEY0db && KEY1db) begin
			din <= dout - 8'b1;	
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

// 16 X 8 synchronous RAM with old data read-during-write behavior
module memory(input logic clk,
		input logic [3:0]  a,
		input logic [7:0]  din,
		input logic we,
		output logic [7:0] dout);

	logic [7:0] 			 mem [15:0];

	always_ff @(posedge clk) begin
		if (we) mem[a] <= din;
		dout <= mem[a];
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
*/
