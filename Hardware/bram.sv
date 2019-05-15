/*
 * Construct BRAM modules for pipeline memory buffers
 */
 
`include "global_variables.sv"

/*
 * Dual read/write port ram
 */
module myNewerBram (
	input logic clk,
	input logic [`nFFT -1:0] aa, ab,
	input logic [(`SFFT_OUTPUT_WIDTH*2) -1:0] da, db, 
	input logic wa, wb,
	output logic [(`SFFT_OUTPUT_WIDTH*2) -1:0] qa, qb);
	
	logic [(`SFFT_OUTPUT_WIDTH*2) -1:0] mem [`NFFT -1:0];
 	
 	always_ff @(posedge clk) begin
 		if (wa) begin
 			mem[aa] <= da;
 			qa <= da;
 		end
 		else begin
 			qa <= mem[aa];
 		end
 	end
 	
 	always_ff @(posedge clk) begin
 		if (wb) begin
 			mem[ab] <= db;
 			qb <= db;
 		end
 		else begin
 			qb <= mem[ab];
 		end
 	end
	
endmodule
