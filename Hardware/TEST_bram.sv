`include "global_variables.sv"
`include "bramNewer.v"

module BRAM_Testbench();

	reg clk = 0;
	
	//Input bus
	logic [`nFFT -1:0] ramBuffer0_address_A = 0;
 	logic ramBuffer0_writeEnable_A = 0;
 	logic [`nFFT -1:0] ramBuffer0_address_B = 0;
 	logic ramBuffer0_writeEnable_B = 0;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInReal_A = 0;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInImag_A = 0;
 	
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInReal_B = 0;
 	logic [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataInImag_B = 0;
 	
 	//Output bus
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutReal_A;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutImag_A;
 	
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutReal_B;
 	wire [`SFFT_OUTPUT_WIDTH -1:0] ramBuffer0_dataOutImag_B;
	 
	//Concatenate dataIn bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataInConcatenated_A;
	assign ramBuffer0_dataInConcatenated = {ramBuffer0_dataInReal_A, ramBuffer0_dataInImag_A};

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataInConcatenated_B;
	assign ramBuffer0_dataInConcatenated = {ramBuffer0_dataInReal_B, ramBuffer0_dataInImag_B};

	//Concatenate dataOut bus
	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataOutConcatenated_A;
	assign ramBuffer0_dataOutConcatenated = {ramBuffer0_dataOutReal_A, ramBuffer0_dataOutImag_A};

	wire [(2*`SFFT_OUTPUT_WIDTH) -1:0] ramBuffer0_dataOutConcatenated_B;
	assign ramBuffer0_dataOutConcatenated = {ramBuffer0_dataOutReal_B, ramBuffer0_dataOutImag_B};

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
	
	initial begin
		ramBuffer0_writeEnable_A = 1;
		ramBuffer0_writeEnable_B = 1;
		
		ramBuffer0_address_A = 1;
		ramBuffer0_address_B = 2;
		
		ramBuffer0_dataInReal_A = 11;
		ramBuffer0_dataInImag_A = 12;
		
		ramBuffer0_dataInReal_B = 21;
		ramBuffer0_dataInImag_B = 22;
		
		#1
		ramBuffer0_address_A = 3;
		ramBuffer0_address_B = 4;
		
		ramBuffer0_dataInReal_A = 31;
		ramBuffer0_dataInImag_A = 32;
		
		ramBuffer0_dataInReal_B = 41;
		ramBuffer0_dataInImag_B = 42;
		
		#2
		ramBuffer0_address_A = 5;
		ramBuffer0_address_B = 6;
		
		ramBuffer0_dataInReal_A = 51;
		ramBuffer0_dataInImag_A = 52;
		
		ramBuffer0_dataInReal_B = 61;
		ramBuffer0_dataInImag_B = 62;
		#1
		ramBuffer0_writeEnable_A = 0;
		ramBuffer0_writeEnable_B = 0;
		
		#1
		ramBuffer0_address_A = 1;
		ramBuffer0_address_B = 2;
		
		#2
		ramBuffer0_address_A = 3;
		ramBuffer0_address_B = 4;
		
		#2
		ramBuffer0_address_A = 5;
		ramBuffer0_address_B = 6;
		
	end
	
	//Clock toggling
	always begin
		#1  //2-step period
		clk <= ~clk;
	end	
		
endmodule
