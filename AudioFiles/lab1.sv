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
	assign HEX0 = 7'b111_1111;

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
