/*
 * Construct BRAM modules for SFFT ROM and for pipeline memory buffers
 */
 
 `include "global_variables.sv"
 
 
 /*
  * NOTE: Not currently in use
  */
 module pipelineBuffer_RAM(
 	input readClk,
 	input writeClk,
 	
 	//Inputs
 	input logic [`nFFT -1:0] read_address_A,
 	input logic [`nFFT -1:0] write_address_A,
 	input logic writeEnable_A,
 	
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] dataInReal_A,
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] dataInImag_A,
 	
 	input logic [`nFFT -1:0] read_address_B,
 	input logic [`nFFT -1:0] write_address_B,
 	input logic writeEnable_B,
 	
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] dataInReal_B,
 	input logic [`SFFT_OUTPUT_WIDTH -1:0] dataInImag_B,
 	
 	//Outputs
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataOutReal_A,
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataOutImag_A,
 	
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataOutReal_B,
 	output logic [`SFFT_OUTPUT_WIDTH -1:0] dataOutImag_B
 	);
 		
	logic [`SFFT_OUTPUT_WIDTH -1:0] Real_Mem [`NFFT -1:0];
 	logic [`SFFT_OUTPUT_WIDTH -1:0] Imag_Mem [`NFFT -1:0];
	
	always @(posedge writeClk) begin
		if (writeEnable_A) begin
			Real_Mem[write_address_A] <= dataInReal_A;
			Imag_Mem[write_address_A] <= dataInImag_A;
		end
		
		if (writeEnable_B) begin
			Real_Mem[write_address_B] <= dataInReal_B;
			Imag_Mem[write_address_B] <= dataInImag_B;
		end
	end
	
	always @(posedge readClk) begin
		dataOutReal_A <= Real_Mem[read_address_A];
		dataOutImag_A <= Imag_Mem[read_address_A];
		
		dataOutReal_B <= Real_Mem[read_address_B];
		dataOutImag_B <= Imag_Mem[read_address_B];
	end
	
	//_______________________________
	//
	// Simulation Probes
	//_______________________________
	
	wire [`SFFT_OUTPUT_WIDTH -1:0] PROBE_Real_Mem [`NFFT -1:0];
	assign PROBE_Real_Mem = Real_Mem;
	
endmodule  //pipelineBuffer_RAM


 /*
  * NOTE: Not currently in use
  
 module kValues_ROM(
 	input clk,
 	
 	//Inputs
 	input [] readAddress_A,
 	input [] readAddress_B,
 	
 	//Outputs
 	output logic [`nFFT -1:0] dataOut_A,
 	output logic [`nFFT -1:0] dataOut_B,
 	);
 		
	logic [`nFFT -1:0] kValues [`nFFT*(`NFFT / 2) -1:0];
	
	//Load values into ROM from generated text files
	initial begin
`ifdef RUNNING_SIMULATION
		//NOTE: These filepaths must be changed to their absolute local paths if simulating with Vsim. Otherwise they should be relative to Hardware directory
		//NOTE: If simulating with Vsim, make sure to run the Matlab script GenerateRomFiles.m if you change any global variables
		
		$readmemh("/user3/fall16/jer2201/notShazam/Hardware/GeneratedParameters/Ks.txt", kValues, 0);
`else
		$readmemh("GeneratedParameters/Ks.txt", kValues, 0);
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
	
endmodule  //kValues_ROM
*/
