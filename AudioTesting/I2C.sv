/*
 * This module acts as the master driver for the I2C bus.
 */
 
 

module I2C_Driver (
	input CLOCK_50,
	input reset,
	//Inputs
	input start,
	output reg communicating,
	
	input [6:0] SlaveAddress,
	input [7:0] RegisterAddress,
	input write,
	input read,
	input [7:0] dataSend,
	output reg [7:0] dataRecieved,
	
	//Outputs
	output FPGA_I2C_SCLK,
	inout FPGA_I2C_SDAT,
	);
	
	parameter SCOUNTER_WIDTH = 7;
	parameter SCOUNTER_MAX = 32;
	parameter CLOCKCOUNTER_WIDTH = 10;
	
	reg SCLK;
	reg [SCOUNTER_WIDTH-1:0] SerialCounter;
	reg SDI;
	reg [CLOCKCOUNTER_WIDTH-1:0] clockCounter;
	wire slowClock = clockCounter[CLOCKCOUNTER_WIDTH-1];
	
	reg [6:0] SlaveAddress_Buffer;
	reg [7:0] RegisterAddress_Buffer;
	reg write_Buffer;
	reg read_Buffer;
	reg [7:0] dataSend_Buffer;
	
	wire [26:0] packet = {SlaveAddress_Buffer, read_Buffer, 0, RegisterAddress_Buffer, 0, dataSend_Buffer, 0}; //Concatenate packet into wire array
	
	//Slow down clock
	always @ (posedge CLOCK_50) clockCounter <= clockCounter + 1;
	
	//Determine if we are at an acknowledge bit 11 20 29
	assign ackBit = ((SerialCounter - 2) % 9) == 0;
	
	assign FPGA_I2C_SCLK = ((SerialCounter >= 4) & (SerialCounter < SCOUNTER_MAX)) ? slowClock : SCLK;

	always @ (posedge slowClock) begin
		if (reset) begin
			communicating <= 0;
			SerialCounter <= 0;
			SCLK <= 1;
			FPGA_I2C_SDAT <= 1;
		end
		else begin
			//Control communicating
			if (start) begin
				communicating <= 1;
				//Buffer I2C packet
				SlaveAddress_Buffer <= SlaveAddress;
				RegisterAddress_Buffer <= RegisterAddress;
				write_Buffer <= write;
				read_Buffer <= read;
				dataSend_Buffer <= dataSend;
			end
			
			//Control SerialCounter
			if (!communicating) begin
				SerialCounter <= 0;
			end
			else begin
				if (SerialCounter < SCOUNTER_MAX) begin
					SerialCounter <= SerialCounter + 1;
				end
				else begin
					SerialCounter <= 0;
				end
			end
			
			//Control SCLK and SDAT
			case (SerialCounter)
				0 : begin
					FPGA_I2C_SDAT <= 1;
					SCLK <= 1;
				end
				
				//Start condition
				1 : FPGA_I2C_SDAT <= 0;
				2 : SCLK <= 0;
				
				SCOUNTER_MAX-2 : begin
					FPGA_I2C_SDAT <= 0;
					SCLK <= 1;
				end
				SCOUNTER_MAX-1 : begin
					FPGA_I2C_SDAT <= 1;
					SCLK <= 1;
					communicating <= 0;
				end
				
				default : begin
					//Slave ack
					if (ackBit) begin
						FPGA_I2C_SDAT <= 1'bz;
					end
					//Default
					else begin
						FPGA_I2C_SDAT <= packet[SerialCounter];
					end
				end
			endcase
		end
	end
endmodule
