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
	//500 Hz test wave
	reg [23:0] testWave [511:0] = '{24'd8388608, 24'd8941642, 24'd9115854, 24'd8791908, 24'd8191706, 24'd7726379, 24'd7714672, 24'd8164605, 24'd8767977, 24'd9111485, 24'd8959829, 24'd8416892, 24'd7854580, 24'd7658072, 24'd7961974, 24'd8558115, 24'd9038146, 24'd9073248, 24'd8639379, 24'd8033733, 24'd7671173, 24'd7800049, 24'd8332081, 24'd8902834, 24'd9121346, 24'd8837940, 24'd8246745, 24'd7752725, 24'd7694278, 24'd8111440, 24'd8718459, 24'd9099533, 24'd8993630, 24'd8473292, 24'd7894946, 24'd7654753, 24'd7917244, 24'd8502614, 24'd9009890, 24'd9091594, 24'd8691759, 24'd8084268, 24'd7685246, 24'd7768020, 24'd8275891, 24'd8860971, 24'd9122487, 24'd8881302, 24'd8302627, 24'd7782847, 24'd7678008, 24'd8059922, 24'd8666983, 24'd9083359, 24'd9023838, 24'd8529189, 24'd7938244, 24'd7655793, 24'd7875313, 24'd8446435, 24'd8977945, 24'd9105765, 24'd8742339, 24'd8136610, 24'd7703497, 24'd7739678, 24'd8220369, 24'd8816302, 24'd9119268, 24'd8921739, 24'd8359019, 24'd7816568, 24'd7665958, 24'd8010356, 24'd8613853, 24'd9063059, 24'd9050272, 24'd8584252, 24'd7984217, 24'd7661186, 24'd7836431, 24'd8389912, 24'd8942500, 24'd9115676, 24'd8790818, 24'd8190449, 24'd7725817, 24'd7715190, 24'd8165848, 24'd8769093, 24'd9111710, 24'd8959008, 24'd8415588, 24'd7853686, 24'd7658200, 24'd7963036, 24'd8559385, 24'd9038752, 24'd9072777, 24'd8638152, 24'd8032592, 24'd7670899, 24'd7800829, 24'd8333382, 24'd8903764, 24'd9121269, 24'd8836907, 24'd8245465, 24'd7752074, 24'd7694702, 24'd8112649, 24'd8719625, 24'd9099857, 24'd8992890, 24'd8471996, 24'd7893981, 24'd7654781, 24'd7918245, 24'd8503903, 24'd9010584, 24'd9091218, 24'd8690570, 24'd8083081, 24'd7684874, 24'd7768718, 24'd8277180, 24'd8861969, 24'd9122510, 24'd8880334, 24'd8301331, 24'd7782111, 24'd7678336, 24'd8061089, 24'd8668190, 24'd9083779, 24'd9023183, 24'd8527908, 24'd7937214, 24'd7655720, 24'd7876247, 24'd8447736, 24'd8978722, 24'd9105486, 24'd8741195, 24'd8135385, 24'd7703030, 24'd7740289, 24'd8221640, 24'd8817362, 24'd9119391, 24'd8920841, 24'd8357716, 24'd7815751, 24'd7666188, 24'd8011475, 24'd8615094, 24'd9063573, 24'd9049706, 24'd8582994, 24'd7983129, 24'd7661012, 24'd7837292, 24'd8391217, 24'd8943355, 24'd9115496, 24'd8789725, 24'd8189193, 24'd7725258, 24'd7715711, 24'd8167091, 24'd8770209, 24'd9111933, 24'd8958186, 24'd8414284, 24'd7852793, 24'd7658330, 24'd7964100, 24'd8560654, 24'd9039357, 24'd9072303, 24'd8636925, 24'd8031451, 24'd7670626, 24'd7801612, 24'd8334684, 24'd8904693, 24'd9121189, 24'd8835873, 24'd8244185, 24'd7751425, 24'd7695129, 24'd8113858, 24'd8720789, 24'd9100178, 24'd8992148, 24'd8470699, 24'd7893018, 24'd7654811, 24'd7919247, 24'd8505191, 24'd9011276, 24'd9090839, 24'd8689380, 24'd8081895, 24'd7684505, 24'd7769418, 24'd8278470, 24'd8862965, 24'd9122530, 24'd8879365, 24'd8300036, 24'd7781377, 24'd7678666, 24'd8062257, 24'd8669396, 24'd9084197, 24'd9022526, 24'd8526627, 24'd7936186, 24'd7655649, 24'd7877182, 24'd8449036, 24'd8979497, 24'd9105205, 24'd8740050, 24'd8134161, 24'd7702565, 24'd7740902, 24'd8222911, 24'd8818420, 24'd9119512, 24'd8919941, 24'd8356412, 24'd7814936, 24'd7666420, 24'd8012595, 24'd8616335, 24'd9064084, 24'd9049138, 24'd8581735, 24'd7982041, 24'd7660842, 24'd7838154, 24'd8392522, 24'd8944209, 24'd9115314, 24'd8788632, 24'd8187937, 24'd7724700, 24'd7716233, 24'd8168336, 24'd8771323, 24'd9112153, 24'd8957362, 24'd8412979, 24'd7851902, 24'd7658463, 24'd7965166, 24'd8561922, 24'd9039960, 24'd9071827, 24'd8635696, 24'd8030312, 24'd7670356, 24'd7802396, 24'd8335985, 24'd8905620, 24'd9121106, 24'd8834838, 24'd8242906, 24'd7750778, 24'd7695557, 24'd8115069, 24'd8721952, 24'd9100497, 24'd8991405, 24'd8469402, 24'd7892056, 24'd7654843, 24'd7920251, 24'd8506479, 24'd9011966, 24'd9090458, 24'd8688190, 24'd8080710, 24'd7684137, 24'd7770120, 24'd8279760, 24'd8863960, 24'd9122548, 24'd8878394, 24'd8298740, 24'd7780645, 24'd7678998, 24'd8063427, 24'd8670601, 24'd9084612, 24'd9021867, 24'd8525345, 24'd7935159, 24'd7655581, 24'd7878119, 24'd8450337, 24'd8980270, 24'd9104921, 24'd8738904, 24'd8132937, 24'd7702102, 24'd7741517, 24'd8224182, 24'd8819478, 24'd9119631, 24'd8919040, 24'd8355108, 24'd7814123, 24'd7666654, 24'd8013716, 24'd8617575, 24'd9064594, 24'd9048568, 24'd8580476, 24'd7980956, 24'd7660673, 24'd7839018, 24'd8393827, 24'd8945060, 24'd9115129, 24'd8787537, 24'd8186683, 24'd7724145, 24'd7716757, 24'd8169581, 24'd8772436, 24'd9112372, 24'd8956536, 24'd8411675, 24'd7851013, 24'd7658598, 24'd7966232, 24'd8563190, 24'd9040560, 24'd9071349, 24'd8634467, 24'd8029173, 24'd7670089, 24'd7803182, 24'd8337287, 24'd8906545, 24'd9121022, 24'd8833801, 24'd8241627, 24'd7750134, 24'd7695988, 24'd8116280, 24'd8723114, 24'd9100814, 24'd8990659, 24'd8468105, 24'd7891096, 24'd7654877, 24'd7921257, 24'd8507767, 24'd9012654, 24'd9090075, 24'd8686998, 24'd8079526, 24'd7683772, 24'd7770823, 24'd8281051, 24'd8864954, 24'd9122564, 24'd8877421, 24'd8297445, 24'd7779915, 24'd7679333, 24'd8064597, 24'd8671805, 24'd9085026, 24'd9021206, 24'd8524063, 24'd7934134, 24'd7655515, 24'd7879057, 24'd8451637, 24'd8981042, 24'd9104635, 24'd8737756, 24'd8131714, 24'd7701641, 24'd7742134, 24'd8225454, 24'd8820533, 24'd9119747, 24'd8918138, 24'd8353805, 24'd7813312, 24'd7666891, 24'd8014839, 24'd8618815, 24'd9065101, 24'd9047996, 24'd8579216, 24'd7979871, 24'd7660507, 24'd7839884, 24'd8395132, 24'd8945910, 24'd9114942, 24'd8786441, 24'd8185428, 24'd7723591, 24'd7717284, 24'd8170827, 24'd8773547, 24'd9112588, 24'd8955709, 24'd8410371, 24'd7850125, 24'd7658735, 24'd7967300, 24'd8564457, 24'd9041159, 24'd9070869, 24'd8633237, 24'd8028036, 24'd7669823, 24'd7803970, 24'd8338589, 24'd8907469, 24'd9120935, 24'd8832763, 24'd8240349, 24'd7749491, 24'd7696421, 24'd8117493, 24'd8724275, 24'd9101128, 24'd8989912, 24'd8466808, 24'd7890137, 24'd7654914, 24'd7922264, 24'd8509054, 24'd9013340, 24'd9089690, 24'd8685805, 24'd8078343, 24'd7683409, 24'd7771529, 24'd8282342, 24'd8865946, 24'd9122578, 24'd8876447, 24'd8296151, 24'd7779187, 24'd7679670, 24'd8065769, 24'd8673009, 24'd9085437, 24'd9020543, 24'd8522780, 24'd7933110, 24'd7655451, 24'd7879997, 24'd8452937, 24'd8981811, 24'd9104347, 24'd8736608, 24'd8130492, 24'd7701183, 24'd7742753, 24'd8226727, 24'd8821588, 24'd9119861, 24'd8917233, 24'd8352501, 24'd7812502, 24'd7667129, 24'd8015962, 24'd8620053, 24'd9065606, 24'd9047422, 24'd8577956, 24'd7978788, 24'd7660343, 24'd7840752, 24'd8396437, 24'd8946759, 24'd9114753, 24'd8785344, 24'd8184175, 24'd7723040, 24'd7717813, 24'd8172073, 24'd8774658, 24'd9112802, 24'd8954879, 24'd8409067, 24'd7849239, 24'd7658874, 24'd7968369, 24'd8565723, 24'd9041755, 24'd9070387, 24'd8632006, 24'd8026900, 24'd7669560, 24'd7804760, 24'd8339890, 24'd8908391, 24'd9120845, 24'd8831723};
	
	reg [8:0] testCounter = 0;
	
	reg [23:0] audioInMono;
	always @ (*) begin
		//audioInMono = adc_right_out + adc_left_out;
		audioInMono = testWave[testCounter];
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
 	wire [`SFFT_OUTPUT_WIDTH -1:0] SFFT_Out ;
 	wire SfftOutputValid;
 	wire outputReadError;
 	wire [`nFFT -1:0] output_address;
 	assign output_address = address[`nFFT +1:2];
 	wire [`SFFT_OUTPUT_WIDTH -1:0] Output_Why;
 
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
	 	.OutputValid(SfftOutputValid),
	 	.Output_Why(Output_Why)
	 	);
	
	//Sample counter
	reg [`TIME_COUNTER_WIDTH -1:0] timeCounter = 0;
	always @(posedge SfftOutputValid) begin
		timeCounter <= timeCounter + 1;
	end
	
	/*
	//Instantiate hex decoders
	hex7seg h5( .a(Output_Why[23:20]),.y(HEX5) ), // left digit
		h4( .a(Output_Why[19:16]),.y(HEX4) ),
		h3( .a(Output_Why[15:12]),.y(HEX3) ),
		h2( .a(Output_Why[11:8]),.y(HEX2) ),
		h1( .a(Output_Why[7:4]),.y(HEX1) ),
		h0( .a(Output_Why[3:0]),.y(HEX0) );
	*/	
	
	//Instantiate hex decoders
	hex7seg h5( .a(adc_out_buffer[23:20]),.y(HEX5) ), // left digit
		h4( .a(adc_out_buffer[19:16]),.y(HEX4) ),
		h3( .a(adc_out_buffer[15:12]),.y(HEX3) ),
		h2( .a(adc_out_buffer[11:8]),.y(HEX2) ),
		h1( .a(adc_out_buffer[7:4]),.y(HEX1) ),
		h0( .a(adc_out_buffer[3:0]),.y(HEX0) );
	

	
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
	always @(*) begin
		if (address < `NFFT*2) begin
			//Convert input address into subset of SFFT_Out
			//NOTE: Each 32bit word is written in reverse byte order, due to endian-ness of software. Avoids need for ntohl conversion
			if (address % 4 == 0) begin
				readdata = Output_Why[7:0];
				//readdata = 8'h11;
			end
			else if (address % 4 == 1) begin
				readdata = Output_Why[15:8];
				//readdata = 8'h22;
			end
			else if (address % 4 == 2) begin
				readdata = Output_Why[23:16];
				//readdata = 8'h33;
			end
			else if (address % 4 == 3) begin
				readdata = Output_Why[31:24];
				//readdata = 8'h44;
			end
		end
		else if (address[15:2] == `NFFT/2) begin
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
		//dac_left_in <= adc_left_out;
		//dac_right_in <= adc_right_out;
		
		dac_left_in <= testWave[testCounter];
		dac_right_in <= testWave[testCounter];
		testCounter <= testCounter + 1;
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



