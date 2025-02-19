// Text overlay generator
// Generates fixed text overlaying the screen
// Uses a font_rom to hold a 5x7 font (2x M9K)
// and a char_rom to hold the text overlay 128 x 30 (4x M9K)
module text_overlay
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	// Video outpus
	output logic overlay,
	output logic [3:0] color,
	// flash serial avalon read 
	input flash_clock,
	output [11:0] flash_addr,
	output logic flash_read,
	input flash_data,
	input	flash_wait,
	input	flash_valid
);

	

	logic [16:0] waddr; // 2^17 bits is full 16Kbytes of flash 
	logic [11:0] waddr12; 
	logic [3:0] cnt12;
	
	always @(posedge flash_clock) begin
		if( reset ) begin
			waddr <= 0;
			cnt12 <= 0;
			waddr12<= 0;
		end else if( waddr != 17'h1FFFF && flash_valid ) begin
			waddr <= waddr + 1;
			if( waddr >= 17'h04000 ) begin // loading text
				cnt12 <= (cnt12 == 11) ? 0 : cnt12 + 1; // rolling count by 12
				waddr12 <= (cnt12 == 11) ? waddr12 + 1 : waddr12;
			end
		end
	end
	
	// Rom Write Flags
	logic we_font;	// 16384x1b rom
	logic we_text; // 4096x12b rom
	assign we_font = ( flash_valid && waddr < 17'h04000 ) ? 1'b1 : 1'b0;
	assign we_text = ( flash_valid && waddr >= 17'h04000 && waddr < 17'h10000 && cnt12 == 11 ) ? 1'b1 : 1'b0;
	
	// Flash Read address // 32 bit word address
	assign flash_addr = { waddr[16:12], 7'b0000_000 }; // in 128 x 32bit = 4Kbit bursts
	
	// Flash read flag on 4Kbit boundaries, hold with wait
	logic pend;
	always @(posedge flash_clock) begin
		if( reset ) begin
			flash_read <= 0;
			pend <= 0;
		end else begin
			if( !pend && !flash_read && waddr[11:0] == 0 ) begin
				flash_read <= 1'b1;
				pend <= 0;
			end else if( flash_read && !flash_wait ) begin
				flash_read <= 1'b0;
				pend <= 1;
			end else if( flash_valid ) begin
				flash_read <= 0;
				pend <= 0;
			end
		end
	end
			
	// Load the font rom because rom init not supported by 'SC' compact devices
	reg font_rom [16383:0]; // indexed by ( col[2:0]<<(3+8) + row[2:0]<<8 + char[7:0] ) 
	always @(posedge flash_clock ) 
		if( we_font ) font_rom[ waddr[13:0] ] <= flash_data;

	// 12 bit shift register for text ram write
	logic [11:0] flash_data12;
	always @( posedge flash_clock )
		if( flash_valid )	
			flash_data12[11:0] <= { flash_data12[10:0], flash_data };		
		
	// Load the overlay text for the screen
	reg [11:0] text_rom [4095:0]; // indexed by { x[6:0], y[4:0] } giving 30 rows of 128 chars
	always @(posedge flash_clock ) 
		if( we_text ) 
			text_rom[ waddr12[11:0] ] <= { flash_data12[10:0], flash_data };
	
	// Generate the timing signals
	
	logic [7:0] char_x;
	logic [7:0] char_y;
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
	
	// Read and overlay the roms
	logic [11:0] charcode;
	logic [3:0] color_reg;
	logic [2:0] cntx6_del;
	logic fontout;
	always @(posedge clk) begin
		// read char rom
		charcode[11:0]  <= text_rom[{ ycnt[8:4], char_x[6:0] }];
		cntx6_del[2:0] <= cntx6[2:0];
		// Read the font rom
		fontout <= font_rom[ { cntx6_del[2:0], ycnt[2:0], charcode[7:0] } ];
		color_reg <= charcode[11:8]; // char color
	end
	
	// Gate overlay to left 128 chars of 30 odd rows 
	assign overlay = ( !ycnt[3] && !char_x[7] ) ? fontout : 1'b0; // only display even lines and first 128 chars
	assign color = color_reg;
endmodule




// Ascii font generator
// The font codes are generated by spreadsheet: font_5x7_gen.xlsx
// input: video sync
// output: char x,y indexing chars places on 6x8 pel grid
// output: binary array of ascii chars rendered over the full screen
// A char can be generated and or'ed into the display
// = ( char_x == x & char_y == y & ascii_char("Y") )
module ascii_font57
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	output logic [7:0] char_x,
	output logic [7:0] char_y,
	output logic [255:0] ascii_char, // supported chars else zero
	output logic [1:0] binary_char, // for binary display
	output logic [15:0]  hex_char  // easy to use for hex display
);


// Character PELs data entry
//     blk  char code
logic [0:8][0:9][7:0] code; // Ascii Code for a give char
//     blk  row char pel
logic [0:8][0:6][0:9][0:4] pel; // pel data
//     blk char  row  pel 
logic [0:8][0:9][0:6][0:4] gated; // pel data gated by position
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
assign pel[2][0] = {50'b10001_10001_10001_10001_10001_11111_00000_00000_00000_11111};
assign pel[2][1] = {50'b10001_10001_10001_10001_10001_00001_00000_00000_00001_00000};
assign pel[2][2] = {50'b10001_10001_10001_01010_10001_00010_00000_00100_00010_00000};
assign pel[2][3] = {50'b10001_10001_10101_00100_01010_00100_00000_00000_00100_00000};
assign pel[2][4] = {50'b10001_10001_10101_01010_00100_01000_00000_00100_01000_00000};
assign pel[2][5] = {50'b10001_01010_11011_10001_00100_10000_00000_00000_10000_00000};
assign pel[2][6] = {50'b01110_00100_10001_10001_00100_11111_00100_00000_00000_00000};
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
assign pel[7][0] = {50'b00000_01010_00000_00010_10000_00000_00100_01000_01110_11000};
assign pel[7][1] = {50'b00000_01010_00100_00100_01000_00000_01000_00100_10001_11001};
assign pel[7][2] = {50'b00000_11111_10101_01000_00100_11111_01000_00100_10001_00010};
assign pel[7][3] = {50'b11111_01010_01110_10000_00010_00000_01000_00100_10001_00100};
assign pel[7][4] = {50'b00000_11111_10101_01000_00100_11111_01000_00100_11011_01000};
assign pel[7][5] = {50'b00000_01010_00100_00100_01000_00000_01000_00100_01010_10011};
assign pel[7][6] = {50'b00000_01010_00000_00010_10000_00000_00100_01000_11011_00011};
assign code[8]   = {8'hC8,8'hC9,8'hCA,8'hCB,8'hCC,8'hCD,8'hCE,8'hCF,8'hD0,8'hD1};
assign pel[8][0] = {50'b00000_11111_11111_11111_00000_00000_11111_00100_00000_11111};
assign pel[8][1] = {50'b00111_00000_11110_01111_00000_00000_11111_01110_00100_11111};
assign pel[8][2] = {50'b00100_00000_11100_00111_10000_00001_01110_11111_01110_11111};
assign pel[8][3] = {50'b00100_00000_11000_00011_11000_00011_01110_00000_11111_11111};
assign pel[8][4] = {50'b10101_00000_10000_00001_11100_00111_00100_00000_01110_11111};
assign pel[8][5] = {50'b01110_00000_00000_00000_11110_01111_00100_00000_00100_11111};
assign pel[8][6] = {50'b00100_00000_00000_00000_11111_11111_00000_00000_00000_11111};

// synthesis translate_off
// take advantage and write out font_rom_init.txt
// simulate testbenche and `define FONT_GEN
// Run in sim to write out this matrix
	logic font_rom [16383:0]; // indexed by ( col[2:0]<<(3+8) + row[2:0]<<8 + char[7:0] ) 
	initial begin
		// zero the rom
		for( int cc = 0; cc < 8; cc++ )
			for( int rr = 0; rr < 8; rr ++ )
				for( int aa = 0; aa < 256; aa++ )
					font_rom[ (cc<<11)+(rr<<8)+aa ] = 0;
		// load the font bits into the ROM
		for( int bb = 0; bb < 9; bb++ ) // number of blocks of 10 chars, extend to array size
			for( int rr = 0; rr < 7; rr++ ) // number of rows in 5x7 font
				for( int cc = 0; cc < 10; cc++ ) // number of chars per block
					for( int pp = 0; pp < 5; pp++ )
						font_rom[ (pp<<11)+(rr<<8)+code[bb][cc] ] = pel[bb][rr][cc][pp];
		// Write out the font file - find it in the sim directory
		$writememb("font_rom_init.txt", font_rom );
	end
// synthesis translate_on


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
	assign char_y[7:0] = { 2'b00, ycnt[8:3] };

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
		for( int bb = 0; bb < 9; bb++ ) 
			for( int rr = 0; rr < 7; rr++ )
				for( int cc = 0; cc < 10; cc++ )
					for( int pp = 0; pp < 5; pp++ )
						gated[bb][cc][rr][pp] = pel[bb][rr][cc][pp] & selx[pp] & sely[rr];
		reduc = 0; 
		for( int bb = 0; bb < 9; bb++ ) 
			for( int cc = 0; cc < 10; cc++ )
				reduc[code[bb][cc]] = |gated[bb][cc]; // Reduction-OR for each char
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
		binary_char[0] = ascii_char["0"];
		binary_char[1] = ascii_char["1"];	
	end

endmodule

module string_overlay
#( 
	parameter LEN = 1 
)
(
	// System
	input clk,
	input reset,
	// Font generator input
	input [7:0] char_x,
	input [7:0] char_y,
	input [255:0] ascii_char, // supported chars else zero
	// Display string and X,Y start 
	input [LEN*8-1:0] str, // input string
	input [7:0] x,
	input [7:0] y,
	// The video output is a single bit
	output logic out 
);	

logic [LEN-1:0] char_overlay;

always_comb begin
	// Loop through chars, index the ascii data, gate with location and pack for OE
	for( int ii = 0; ii < LEN; ii++ ) begin
		char_overlay[ii] = ascii_char[str[(LEN-ii)*8-1 -:8]] 
		                 & (((char_x == (x + ii))) ? 1'b1 : 1'b0 )
						     & (((char_y ==  y      )) ? 1'b1 : 1'b0 ); 	
	end
	out = |char_overlay; // Reduction-OR
end	
	
endmodule

module hex_overlay
#( 
	parameter LEN = 1 
)
(
	// System
	input clk,
	input reset,
	// Font generator input
	input [7:0] char_x,
	input [7:0] char_y,
	input [15:0] hex_char, // supported chars else zero
	// Display string and X,Y start 
	input [LEN*4-1:0] in, // input number
	input [7:0] x,
	input [7:0] y,
	// The video output is a single bit
	output logic out 
);	

logic [LEN-1:0] char_overlay;

always_comb begin
	// Loop through chars, index the ascii data, gate with location and pack for OE
	for( int ii = 0; ii < LEN; ii++ ) begin
		char_overlay[ii] = hex_char[in[(LEN-ii)*4-1 -:4]] 
		                 & (((char_x == (x + ii))) ? 1'b1 : 1'b0 )
						     & (((char_y ==  y      )) ? 1'b1 : 1'b0 ); 	
	end
	out = |char_overlay; // Reduction-OR
end	
endmodule
		
module bin_overlay
#( 
	parameter LEN = 1 
)
(
	// System
	input clk,
	input reset,
	// Font generator input
	input [7:0] char_x,
	input [7:0] char_y,
	input [1:0] bin_char, // supported chars else zero
	// Display string and X,Y start 
	input [LEN-1:0] in, // input string
	input [7:0] x,
	input [7:0] y,
	// The video output is a single bit
	output logic out 
);	

logic [LEN-1:0] char_overlay;

always_comb begin
	// Loop through chars, index the ascii data, gate with location and pack for OE
	for( int ii = 0; ii < LEN; ii++ ) begin
		char_overlay[ii] = bin_char[in[(LEN-ii)-1]] 
		                 & (((char_x == (x + ii))) ? 1'b1 : 1'b0 )
						     & (((char_y ==  y      )) ? 1'b1 : 1'b0 ); 	
	end
	out = |char_overlay; // Reduction-OR
end	
endmodule	

