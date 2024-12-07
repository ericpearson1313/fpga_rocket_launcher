// 5x7 font display engine
module font57
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	output [7:0] char_x,
	output [7:0] char_y,
	output [15:0] char_data
);

logic [2:0] cntx6;
logic [2:0] cnty8;
logic [8:0] ycnt;
logic [5:0] bitidx;
logic blank_d1;

	always @(posedge clk) begin
		if( reset ) begin
			char_x <= 0;
			cntx6 <= 5;
			ycnt <= 0;
			blank_d1 <= 0;
		end else begin
			blank_d1 <= blank;
			cntx6 <= ( blank || cntx6 == 0 ) ? 5 : cntx6 - 1;
			char_x <= ( blank ) ? 0 : ( cntx6 == 0 ) ? char_x + 1 : char_x;
			ycnt <= ( vsync ) ? 0 : 
		        ( blank && !blank_d1 ) ? ycnt + 1 : ycnt;
		end
	end
	assign cnty8[2:0] = ~ycnt[2:0];
	assign char_y[6:0] = { 1'b0, ycnt[8:3] };
	assign bitidx[5:0] = { 2'b00, cnty8[2:0], 1'B0 } +  { 1'b0, cnty8[2:0], 2'b00 } + { 3'b000, cntx6[2:0] };

logic [47:0] hex_0={ 6'b000000,
							6'b011100,
							6'b100010,
							6'b100110,
							6'b101010,
							6'b110010,
							6'b100010,
							6'b011100 };

logic [47:0] hex_1={ 6'b000000,
							6'b001000,
							6'b011000,
							6'b001000,
							6'b001000,
							6'b001000,
							6'b001000,
							6'b011100 };

logic [47:0] hex_2={ 6'b000000,
							6'b011100,
							6'b100010,
							6'b000010,
							6'b011100,
							6'b100000,
							6'b100000,
							6'b111110 };

logic [47:0] hex_3={ 6'b000000,
							6'b011100,
							6'b100010,
							6'b000010,
							6'b001100,
							6'b000010,
							6'b100010,
							6'b011100 };

logic [47:0] hex_4={ 6'b000000,
							6'b000100,
							6'b001100,
							6'b010100,
							6'b100100,
							6'b111110,
							6'b000100,
							6'b000100 };

logic [47:0] hex_5={ 6'b000000,
							6'b111110,
							6'b100000,
							6'b100000,
							6'b111100,
							6'b000010,
							6'b100010,
							6'b011100 };

logic [47:0] hex_6={ 6'b000000,
							6'b000110,
							6'b001000,
							6'b010000,
							6'b111100,
							6'b100010,
							6'b100010,
							6'b011100 };

logic [47:0] hex_7={ 6'b000000,
							6'b111110,
							6'b000010,
							6'b000010,
							6'b000100,
							6'b001000,
							6'b010000,
							6'b100000 };

logic [47:0] hex_8={ 6'b000000,
							6'b011100,
							6'b100010,
							6'b100010,
							6'b011100,
							6'b100010,
							6'b100010,
							6'b011100 };

logic [47:0] hex_9={ 6'b000000,
							6'b011100,
							6'b100010,
							6'b100010,
							6'b011110,
							6'b000010,
							6'b000100,
							6'b011000 };

logic [47:0] hex_A={ 6'b000000,
							6'b001000,
							6'b010100,
							6'b100010,
							6'b100010,
							6'b111110,
							6'b100010,
							6'b100010 };

logic [47:0] hex_B={ 6'b000000,
							6'b111100,
							6'b100010,
							6'b100010,
							6'b111100,
							6'b100010,
							6'b100010,
							6'b111100 };

logic [47:0] hex_C={ 6'b000000,
							6'b011100,
							6'b100010,
							6'b100000,
							6'b100000,
							6'b100000,
							6'b100010,
							6'b011100 };

logic [47:0] hex_D={ 6'b000000,
							6'b111100,
							6'b100010,
							6'b100010,
							6'b100010,
							6'b100010,
							6'b100010,
							6'b111100 };

logic [47:0] hex_E={ 6'b000000,
							6'b111110,
							6'b100000,
							6'b100000,
							6'b111100,
							6'b100000,
							6'b100000,
							6'b111110 };

logic [47:0] hex_F={ 6'b000000,
							6'b111110,
							6'b100000,
							6'b100000,
							6'b111100,
							6'b100000,
							6'b100000,
							6'b100000 };
								
	always @( posedge clk )  begin
		char_data['h0] <= hex_0[bitidx];
		char_data['h1] <= hex_1[bitidx];									
		char_data['h2] <= hex_2[bitidx];									
		char_data['h3] <= hex_3[bitidx];									
		char_data['h4] <= hex_4[bitidx];									
		char_data['h5] <= hex_5[bitidx];									
		char_data['h6] <= hex_6[bitidx];									
		char_data['h7] <= hex_7[bitidx];									
		char_data['h8] <= hex_8[bitidx];									
		char_data['h9] <= hex_9[bitidx];									
		char_data['hA] <= hex_A[bitidx];									
		char_data['hB] <= hex_B[bitidx];									
		char_data['hC] <= hex_C[bitidx];									
		char_data['hD] <= hex_D[bitidx];									
		char_data['hE] <= hex_E[bitidx];									
		char_data['hF] <= hex_F[bitidx];
    end
endmodule

module ascii_font57
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	output [7:0] char_x,
	output [7:0] char_y,
	output [255:0] ascii_char, // supported chars else zero
	output [15:0]  hex_char  // easy to use for hex display
);


// Character PELs data entry
//     blk  char code
logic [0:7][0:9][7:0] code; // Ascii Code for a give char
//     blk  row char pel
logic [0:7][0:6][0:9][0:4] pel; // pel data
//     blk char  row  pel 
logic [0:7][0:9][0:6][0:4] gated; // pel data gated by position
//     ASCII
logic [255:0] reduc; // Reduciton ORed ASCII ordered 	

assign code[0]   = {8'h41,8'h42,8'h43,8'h44,8'h45,8'h46,8'h47,8'h48,8'h49,8'h4A};
assign pel[0][0] = {50'b01110_11110_01110_11110_11111_11111_01110_10001_01110_00001};
assign pel[0][1] = {50'b10001_10001_10001_10001_10000_10000_10001_10001_00100_00001};
assign pel[0][2] = {50'b10001_10001_10000_10001_10000_10000_10000_10001_00100_00001};
assign pel[0][3] = {50'b10001_11110_10000_10001_11110_11110_10111_11111_00100_00001};
assign pel[0][4] = {50'b11111_10001_10000_10001_10000_10000_10001_10001_00100_10001};
assign pel[0][5] = {50'b10001_10001_10001_10001_10000_10000_10001_10001_00100_10001};
assign pel[0][6] = {50'b10001_11110_01110_11110_11111_10000_01110_10001_01110_01110};
assign code[1]   = {8'h4B,8'h4C,8'h4D,8'h4E,8'h4F,8'h50,8'h51,8'h52,8'h53,8'h54};
assign pel[1][0] = {50'b10001_10000_10001_10001_01110_11110_01110_11110_01110_11111};
assign pel[1][1] = {50'b10010_10000_11011_11001_10001_10001_10001_10001_10001_00100};
assign pel[1][2] = {50'b10100_10000_10101_10101_10001_10001_10001_10001_10000_00100};
assign pel[1][3] = {50'b11000_10000_10101_10011_10001_11110_10001_11110_01110_00100};
assign pel[1][4] = {50'b10100_10000_10001_10001_10001_10000_10101_10100_00001_00100};
assign pel[1][5] = {50'b10010_10000_10001_10001_10001_10000_10010_10010_10001_00100};
assign pel[1][6] = {50'b10001_11111_10001_10001_01110_10000_01101_10001_01110_00100};
assign code[2]   = {8'h55,8'h56,8'h57,8'h58,8'h59,8'h5A,8'h2E,8'h3A,8'h2F,8'h2C};
assign pel[2][0] = {50'b10001_10001_10001_10001_10001_11111_00000_00000_00000_00000};
assign pel[2][1] = {50'b10001_10001_10001_10001_10001_00001_00000_00000_00001_00000};
assign pel[2][2] = {50'b10001_10001_10001_01010_10001_00010_00000_00100_00010_00000};
assign pel[2][3] = {50'b10001_10001_10101_00100_01010_00100_00000_00000_00100_00000};
assign pel[2][4] = {50'b10001_10001_10101_01010_00100_01000_00000_00100_01000_01100};
assign pel[2][5] = {50'b10001_01010_11011_10001_00100_10000_00000_00000_10000_00100};
assign pel[2][6] = {50'b01110_00100_10001_10001_00100_11111_00100_00000_00000_01000};
assign code[3]   = {8'h30,8'h31,8'h32,8'h33,8'h34,8'h35,8'h36,8'h37,8'h38,8'h39};
assign pel[3][0] = {50'b01110_00100_01110_11110_10001_11111_01110_11111_01110_01110};
assign pel[3][1] = {50'b10001_01100_10001_00001_10001_10000_10001_00001_10001_10001};
assign pel[3][2] = {50'b10011_00100_00001_00001_10001_10000_10000_00001_10001_10001};
assign pel[3][3] = {50'b10101_00100_00010_01110_11111_11110_11110_00010_01110_01111};
assign pel[3][4] = {50'b11001_00100_00100_00001_00001_00001_10001_00100_10001_00001};
assign pel[3][5] = {50'b10001_00100_01000_00001_00001_00001_10001_00100_10001_10001};
assign pel[3][6] = {50'b01110_01110_11111_11110_00001_11110_01110_00100_01110_01110};
assign code[4]   = {8'h61,8'h62,8'h63,8'h64,8'h65,8'h66,8'h67,8'h68,8'h69,8'h6A};
assign pel[4][0] = {50'b00000_10000_00000_00010_00000_00110_00000_10000_00100_00010};
assign pel[4][1] = {50'b01100_10000_01100_00010_01100_01001_01110_10000_00000_00000};
assign pel[4][2] = {50'b10010_10000_10010_00010_10010_11100_10010_10000_00100_00010};
assign pel[4][3] = {50'b00010_11100_10000_01110_11110_01000_11110_11100_00100_00010};
assign pel[4][4] = {50'b01110_10010_10000_10010_10000_01000_00010_10010_00100_00010};
assign pel[4][5] = {50'b10010_10010_10010_10010_10010_01000_00010_10010_00100_10010};
assign pel[4][6] = {50'b01100_11100_01100_01110_01100_01000_11100_10010_00100_01100};
assign code[5]   = {8'h6B,8'h6C,8'h6D,8'h6E,8'h6F,8'h70,8'h71,8'h72,8'h73,8'h74};
assign pel[5][0] = {50'b10000_01100_00000_00000_00000_00000_00000_00000_00000_01000};
assign pel[5][1] = {50'b10000_00100_11110_11100_01100_11100_01110_10100_01100_01000};
assign pel[5][2] = {50'b10010_00100_10101_10010_10010_10010_10010_11010_10010_11100};
assign pel[5][3] = {50'b10100_00100_10101_10010_10010_11100_10010_10000_01000_01000};
assign pel[5][4] = {50'b11000_00100_10101_10010_10010_10000_01110_10000_00100_01000};
assign pel[5][5] = {50'b10100_00100_10101_10010_01100_10000_00010_10000_10010_01010};
assign pel[5][6] = {50'b10010_01110_00000_00000_00000_00000_00010_00000_01100_01100};
assign code[6]   = {8'h75,8'h76,8'h77,8'h78,8'h79,8'h7A,8'h22,8'h21,8'h3F,8'h2B};
assign pel[6][0] = {50'b00000_00000_00000_00000_00000_00000_01010_00100_01110_00000};
assign pel[6][1] = {50'b10010_10001_10001_10010_10010_11110_01010_00100_10001_00100};
assign pel[6][2] = {50'b10010_10001_10001_10010_10010_00010_00000_00100_10001_00100};
assign pel[6][3] = {50'b10010_10001_10101_01100_01110_00100_00000_00100_00010_11111};
assign pel[6][4] = {50'b10010_01010_10101_10010_00010_01000_00000_00100_00100_00100};
assign pel[6][5] = {50'b01110_00100_01110_10010_00010_10000_00000_00000_00000_00100};
assign pel[6][6] = {50'b00000_00000_00000_00000_11100_11110_00000_00100_00100_00000};
assign code[7]   = {8'h2D,8'h23,8'h2A,8'h3C,8'h3E,8'h3D,8'h28,8'h29,8'h24,8'h25};
assign pel[7][0] = {50'b00000_01010_00000_00010_10000_00000_00100_01000_00100_11000};
assign pel[7][1] = {50'b00000_01010_00100_00100_01000_00000_01000_00100_11111_11001};
assign pel[7][2] = {50'b00000_11111_10101_01000_00100_11111_01000_00100_10000_00010};
assign pel[7][3] = {50'b11111_01010_01110_10000_00010_00000_01000_00100_11111_00100};
assign pel[7][4] = {50'b00000_11111_10101_01000_00100_11111_01000_00100_00001_01000};
assign pel[7][5] = {50'b00000_01010_00100_00100_01000_00000_01000_00100_11111_10011};
assign pel[7][6] = {50'b00000_01010_00000_00010_10000_00000_00100_01000_00100_00011};


logic [2:0] cntx6;
logic [8:0] ycnt;
logic blank_d1;

	always @(posedge clk) begin
		if( reset ) begin
			char_x <= 0;
			cntx6 <= 0;
			ycnt <= 0;
			blank_d1 <= 0;
		end else begin
			blank_d1 <= blank;
			cntx6 <= ( blank || cntx6 == 5 ) ? 0 : cntx6 + 1;
			char_x <= ( blank ) ? 0 : ( cntx6 == 5 ) ? char_x + 1 : char_x;
			ycnt <= ( vsync ) ? 0 : 
		        ( blank && !blank_d1 ) ? ycnt + 1 : ycnt;
		end
	end
	assign char_y[6:0] = { 1'b0, ycnt[8:3] };

	// Breadk out pel corrdiates to one hot x and y selects
   logic [0:4] selx;
	logic [0:6] sely;
	
	always_comb begin : _one_hot_char_xy
		// one-hot X
		for( int ii = 0; ii < 5; ii++ )
			selx[ii] = ( cntx6 == ii ) ? 1'b1 : 1'b0; // 5 pels left justified in 6
		// one-hot Y
		for( int ii = 0; ii < 7; ii++ )
			sely[ii] = ( ycnt[2:0] == (ii+1) ) ? 1'b1 : 1'b0; // 7 pels lower justified in 8
	end			

	// Gate the pels based on X,Y location in char and reduction OR 
	// and packing in ASCII order with default zero.
	
	always_comb begin : _char_gating
		// gate the PELS with the within char positions
		for( int bb = 0; bb < 8; bb++ ) 
			for( int rr = 0; rr < 7; rr++ )
				for( int cc = 0; cc < 10; cc++ )
					for( int pp = 0; pp < 5; pp++ )
						gated[bb][cc][rr][pp] = pel[bb][rr][cc][pp] & selx[pp] & sely[rr];
		reduc = 0; 
		for( int bb = 0; bb < 8; bb++ ) 
			for( int cc = 0; cc < 10; cc++ )
				reduc[code[bb][cc]] = !gated[bb][cc]; // Reduciton-OR for the win!
	end
	
	always @(posedge clk)
		ascii_char <= reduc;
	
	// Map hex chars
	always_comb begin
		hex_char['h0] = ascii_char["0"];
		hex_char['h1] = ascii_char["1"];
		hex_char['h2] = ascii_char["2"];
		hex_char['h3] = ascii_char["3"];
		hex_char['h4] = ascii_char["4"];
		hex_char['h5] = ascii_char["5"];
		hex_char['h6] = ascii_char["6"];
		hex_char['h7] = ascii_char["7"];
		hex_char['h8] = ascii_char["8"];
		hex_char['h9] = ascii_char["9"];
		hex_char['hA] = ascii_char["A"];
		hex_char['hB] = ascii_char["B"];
		hex_char['hC] = ascii_char["C"];
		hex_char['hD] = ascii_char["D"];
		hex_char['hE] = ascii_char["E"];
		hex_char['hF] = ascii_char["F"];		
	end

endmodule


														 