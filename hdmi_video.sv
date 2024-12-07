


module TDMS_encoder 
// translated from VHDL orginally by MikeField <hamster@snap.net.nz>
// re-written to closer match DVI-1.0 spec
(
	input clk,        // pixel rate clock
	input [7:0] data, // raw 8 bit video
	input [1:0] c, 	// control bits {c1,c0}
	input blank,      // !den == video blanking
	output [9:0] encoded // encoded pixel
);

logic [8:0] xored, xnored;
logic [3:0] ones;
logic [8:0] data_word, data_word_inv;
logic [3:0] data_word_disparity;
logic [3:0] dc_bias = 4'b0000;

// Work our the two different encodings for the byte

assign xored[0] = data[0];
assign xored[1] = data[1] ^ xored[0];
assign xored[2] = data[2] ^ xored[1];
assign xored[3] = data[3] ^ xored[2];
assign xored[4] = data[4] ^ xored[3];
assign xored[5] = data[5] ^ xored[4];
assign xored[6] = data[6] ^ xored[5];
assign xored[7] = data[7] ^ xored[6];
assign xored[8] = 1'b1;

assign xnored[0] = data[0];
assign xnored[1] = data[1] ~^ xnored[0];
assign xnored[2] = data[2] ~^ xnored[1];
assign xnored[3] = data[3] ~^ xnored[2];
assign xnored[4] = data[4] ~^ xnored[3];
assign xnored[5] = data[5] ~^ xnored[4];
assign xnored[6] = data[6] ~^ xnored[5];
assign xnored[7] = data[7] ~^ xnored[6];
assign xnored[8] = 1'b0;

// Count how many ones are set in data
assign ones[3:0]  = (({ 3'b000, data[0] } 
						+   { 3'b000, data[1] }) 
						+  ({ 3'b000, data[2] } 
						+   { 3'b000, data[3] }))
                  + (({ 3'b000, data[4] } 
						+   { 3'b000, data[5] }) 
						+  ({ 3'b000, data[6] } 
						+   { 3'b000, data[7] }));
 
// Decide which encoding to use
assign data_word = ( ones > 4'd4 || ( ones == 4'd4 && data[0] == 1'b0 )) ? xnored : xored;

// Work out the DC bias of the dataword;
assign data_word_disparity[3:0]  = (({ 3'b110, data_word[0] } 
											+   { 3'b000, data_word[1] }) 
											+  ({ 3'b000, data_word[2] } 
											+   { 3'b000, data_word[3] }))
											+ (({ 3'b000, data_word[4] } 
											+   { 3'b000, data_word[5] }) 
											+  ({ 3'b000, data_word[6] } 
											+   { 3'b000, data_word[7] }));		
	
// Now work out what the output should be
always @(posedge clk) begin
	if( blank == 1'b1 ) begin
		encoded <=  ( c[1:0] == 2'b00 ) ? 10'b1101010100 :
						( c[1:0] == 2'b01 ) ? 10'b0010101011 :
						( c[1:0] == 2'b10 ) ? 10'b0101010100 : 
					   /*c[1:0] == 2'b11*/   10'b1010101011 ;
		dc_bias <= 4'd0;
	end else begin 
		if( dc_bias == 4'd0 || data_word_disparity == 4'd0 ) begin // dataword has no disparity
			encoded <= ( data_word[8] ) ? { 2'b01,  data_word[7:0] } : 
			                              { 2'b10, ~data_word[7:0] } ;
			dc_bias <= ( data_word[8] ) ? dc_bias + data_word_disparity : 
			                              dc_bias - data_word_disparity;
	   end else begin
		   if( ( dc_bias[3] == 1'b0 && data_word_disparity[3] == 1'b0 ) ||
		       ( dc_bias[3] == 1'b1 && data_word_disparity[3] == 1'b1 ) ) begin
				encoded <= { 1'b1, data_word[8], ~data_word[7:0] };
				dc_bias <= dc_bias + {3'b000,  data_word[8]} - data_word_disparity;
		   end else begin
				encoded <= { 1'b0, data_word[8],  data_word[7:0] };
				dc_bias <= dc_bias - {3'b000, ~data_word[8]} + data_word_disparity;
			end
		end
	end
end
												
endmodule // TDMS_encoder

//////////////////////////////////////////

module video_encoder
// Convert RGB video and sync into HDMI data for output to DDR I/O
(
	// Clock
	input clk,	// Pixel clk
	input clk5,	// 5x pixel clock for DVI output (2x)
	input reset,

	// HDMI Output
	output [7:0] hdmi_data, // ddr data for the HDMI port, sync with 5x hdmi clk
	
	// Video Sync Interface, pix clock sync
	input blank,
	input hsync,
	input vsync,
	
	// VGA baseband pixel data
	input [7:0] red,
	input [7:0] green,
	input [7:0] blue
);

// TDMS encode each channel.

	logic [9:0] enc_red, enc_green, enc_blue;
	
	TDMS_encoder _enc_red(   .clk( clk ),.data( red ),  .c( 2'b00 ),         .blank( blank ),.encoded( enc_red   ) );
	TDMS_encoder _enc_blue(  .clk( clk ),.data( blue ), .c({ !vsync, !hsync }),.blank( blank ),.encoded( enc_blue  ) );
	TDMS_encoder _enc_green( .clk( clk ),.data( green ),.c( 2'b00 ),         .blank( blank ),.encoded( enc_green ) );

// Determine clk5 load phase;
	logic toggle; // cross phase signal
	always @(posedge clk) toggle <= !toggle;
	
	logic [5:0] tdelay;
	logic [9:0] shift_d2, shift_d1, shift_d0, shift_ck;
	always @(posedge clk5) begin
			tdelay[5:0] <= { tdelay[4:0], toggle };
			if( tdelay[3] ^ tdelay[4] ) begin // load
				shift_d0[9:0] <= enc_blue;
				shift_d1[9:0] <= enc_green;
				shift_d2[9:0] <= enc_red;
				shift_ck[9:0] <= 10'b0000011111;
			end else begin
				shift_d2[9:0] <= { 2'b00, shift_d2[9:2] };
				shift_d1[9:0] <= { 2'b00, shift_d1[9:2] };
				shift_d0[9:0] <= { 2'b00, shift_d0[9:2] };
				shift_ck[9:0] <= { 2'b00, shift_ck[9:2] };
			end
	end
	assign hdmi_data = { shift_d2[1], shift_d1[1], shift_d0[1], shift_ck[1], 
	                     shift_d2[0], shift_d1[0], shift_d0[0], shift_ck[0] };	
endmodule // video_encoder0

module vga_sync // Generate a video sync
(
	input clk,	// Pixel clk
	input reset,
	output blank,
	output hsync,
	output vsync
);

// hcnt, vcnt - free running raw counters for 800x525 video frame (including hvsync)
logic [9:0] hcnt, vcnt;
always @(posedge clk) begin
	if( reset ) begin
		hcnt <= 0;
		vcnt <= 0;
		hsync <= 1'b0;
		vsync <= 1'b0;
		blank <= 1'b0; // 1?
	end else begin 
		// free run hcnt vcnt 800 x 525
		if( hcnt < (800-1) ) begin
			hcnt <= hcnt + 1;
			vcnt <= vcnt;
		end else begin
			hcnt <= 0;
			if( vcnt < (525-1)) begin 
				vcnt <= vcnt + 1;
			end else begin
				vcnt <= 0;
			end
		end
		// Derive sync and blanking signals from the counters
		blank <= ( hcnt >= 640 || vcnt >= 480 ) ? 1'b1 : 1'b0;
		hsync <= ( hcnt >= 656 && hcnt < 752 ) ? 1'b1 : 1'b0;
		vsync <= ( vcnt >= 490 && vcnt < 492 ) ? 1'b1 : 1'b0;
	end
end
endmodule // vga_sync

module vga_800x480_sync // Generate a video sync
#(
// Video Timing Counts
parameter VERT		= 480,
parameter VFRONT 	= 10,
parameter VSYNCP 	= 2,
parameter VBACK	= 33,
parameter HORIZ   = 800,
parameter HFRONT 	= 40,
parameter HSYNCP 	= 128,
parameter HBACK	= 88
)
(
	input clk,	// Pixel clk
	input reset,
	output blank,
	output hsync,
	output vsync
);


// hcnt, vcnt - free running raw counters for 800x525 video frame (including hvsync)
logic [11:0] hcnt, vcnt;
always @(posedge clk) begin
	if( reset ) begin
		hcnt <= 0;
		vcnt <= 0;
		hsync <= 1'b0;
		vsync <= 1'b0;
		blank <= 1'b0;
	end else begin 
		// free run hcnt vcnt 800 x 525
		if( hcnt < (HORIZ+HFRONT+HSYNCP+HBACK-1) ) begin
			hcnt <= hcnt + 1;
			vcnt <= vcnt;
		end else begin
			hcnt <= 0;
			if( vcnt < (VERT+VFRONT+VSYNCP+VBACK-1)) begin 
				vcnt <= vcnt + 1;
			end else begin
				vcnt <= 0;
			end
		end
		// Derive sync and blanking signals from the counters
		blank <= ( hcnt >= HORIZ || vcnt >= VERT ) ? 1'b1 : 1'b0;
		hsync <= ( hcnt >= HORIZ+HFRONT && hcnt < HORIZ+HFRONT+HSYNCP ) ? 1'b1 : 1'b0;
		vsync <= ( vcnt >= VERT +VFRONT && vcnt < VERT +VFRONT+VSYNCP ) ? 1'b1 : 1'b0;
	end
end
endmodule // vga_800x480 sync


module test_pattern
// Create a test patern
// 13 color bars
(
	// Clock
	input clk,	// Pixel clk
	input reset,

	// Video Sync Interface, pix clock sync
	input blank,
	input hsync,
	input vsync,
	
	// VGA baseband pixel data
	output [7:0] red,
	output [7:0] green,
	output [7:0] blue
);

logic [9:0] xcnt, ycnt;
logic [3:0] barcnt;
logic [5:0] cnt50;
logic blank_d1;

always @(posedge clk) begin
	if ( reset ) begin
		xcnt <= 0;
		ycnt <= 0;
		blank_d1 <= 0;
	end else begin
		blank_d1 <= blank;
		cnt50 <= ( blank || cnt50 == 61 ) ? 0 : cnt50 + 1; 
		barcnt <= ( blank ) ? 0 : ( cnt50 == 61 ) ? barcnt + 1 : barcnt;
		xcnt <= ( blank ) ? 0 : xcnt + 1;
		ycnt <= ( vsync ) ? 0 : 
		        ( blank && !blank_d1 ) ? ycnt + 1 : ycnt;
	end
end

// Color outputs a function of location
assign { red, green, blue } = // smpte color bars
		( barcnt == 4'h0 ) ? 24'hc0c0c0 :
		( barcnt == 4'h1 ) ? 24'hc0c000 :
		( barcnt == 4'h2 ) ? 24'h00c000 :
		( barcnt == 4'h3 ) ? 24'h00c0c0 :
		( barcnt == 4'h4 ) ? 24'hc000c0 :
		( barcnt == 4'h5 ) ? 24'hc00000 :
		( barcnt == 4'h6 ) ? 24'h0000c0 :
		( barcnt == 4'h7 ) ? 24'h131313 :
		( barcnt == 4'h8 ) ? 24'h00214c :
		( barcnt == 4'h9 ) ? 24'hffffff :
		( barcnt == 4'ha ) ? 24'h32006a :
		( barcnt == 4'hb ) ? 24'h090909 :
		( barcnt == 4'hc ) ? 24'h1d1d1d : 
		                     24'h000000 ;
											
//assign red   = {xcnt[6],{7{ycnt[5]}}};
//assign green = {xcnt[7],{7{ycnt[6]}}};
//assign blue  = {xcnt[8],{7{ycnt[7]}}};

endmodule // test_pattern

module video
(
	input	clk,
	input clk5,
	input reset,
	output [7:0] hdmi_data,
	input [11:0] ad_a0,
	input [11:0] ad_a1,
	input [11:0] ad_b0,
	input [11:0] ad_b1,
	input ad_strobe,
	input ad_clk,
	input [3:0] diag,
	input	[35:0] id,
	input [4:0] key
);
	
	logic [7:0] red, green, blue;
	logic blank, hsync, vsync;
	
	// sych generator
	vga_800x480_sync _sync
	(
		.clk(   clk   ),	
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync )
	);
	
	// test pattern gen
	test_pattern _testgen 
	(
		.clk( clk     ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.red	( red   ),
		.green( green ),
		.blue	( blue  )
	);
	
	// Font Generator
	logic [7:0] char_x, char_y;
	logic [15:0] char_data;
	
	ascii_font57 _font
	(
		.clk( clk ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.char_x( char_x ), // 0 to 105 chars horizontally
		.char_y( char_y ), // o to 59 rows vertically
		//.char_data( char_data )
		.hex_char( char_data ),
		.ascii_char( )
	);
	
	// Process ADC diag looking for 0's and holding till vsync
	// ensures zero's will be seen by the eye. (1/10 sec?)
	logic [3:0] diag_reg;
	logic [21:0] tenth;
	always @(posedge clk) begin
		tenth <= tenth + 1;
		diag_reg <= ( tenth == 0 ) ? diag : diag & diag_reg;
	end


	// snapshot display values during vsync
	logic [11:0] value_1, value_2, value_3, value_4, value_5;
	logic [4:0] key_reg;
	always @(posedge clk) begin
		if( vsync ) begin
			value_1[11:0] <= ad_a0;
			value_2[11:0] <= ad_a1;
			value_3[11:0] <= ad_b0;
			value_4[11:0] <= ad_b1;
			value_5[11:0] <= 12'hdef;
			key_reg <= key;
		end
	end
	
	logic char_bit;
	assign char_bit = ( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h10 ) ? char_data[{id[35], id[26], id[17], id[8]}] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h12 ) ? char_data['h1] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h13 ) ? char_data['h2] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h14 ) ? char_data['h3] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h15 ) ? char_data['h4] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h16 ) ? char_data['h5] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h18 ) ? char_data[id[34:31]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h19 ) ? char_data[id[30:27]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h1A ) ? char_data[id[25:22]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h1B ) ? char_data[id[21:18]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h1C ) ? char_data[id[16:13]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h1D ) ? char_data[id[12: 9]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h1E ) ? char_data[id[ 7: 4]] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h1F ) ? char_data[id[ 3: 0]] : 
							( char_y[6:0] == 7'h5 && char_x[6:0] == 7'h1D && key_reg[4] == 1 ) ? char_data[key_reg[3:0]] : 0;
	

	

	
	// 4ch Oscilloscope mem & vga display
	logic [7:0] scope_red, scope_green, scope_blue;
	vga_scope _scope(
		.clk(   clk ),
		.reset( reset ),
		// video sync 
		.blank( blank ), 
		.hsync( hsync ),
		.vsync( vsync ),
		// capture inputs
		.ad_a0( ad_a0 ),
		.ad_a1( ad_a1 ),
		.ad_b0( ad_b0 ),
		.ad_b1( ad_b1 ),
		.ad_strobe( ad_strobe ),
		.ad_clk( ad_clk ),
		// video output
		.red(   scope_red ),
		.green( scope_green ),
		.blue(  scope_blue )
	);
	
	
	// 12bit hex overlays(4)
	logic hex_str;
	assign hex_str = 	( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h1B ) ? char_data[value_1[11:8]] :
							( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h1C ) ? char_data[value_1[ 7:4]] :
							( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h1D ) ? char_data[value_1[ 3:0]] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h1B ) ? char_data[value_2[11:8]] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h1C ) ? char_data[value_2[ 7:4]] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h1D ) ? char_data[value_2[ 3:0]] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h1B ) ? char_data[value_3[11:8]] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h1C ) ? char_data[value_3[ 7:4]] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h1D ) ? char_data[value_3[ 3:0]] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h1B ) ? char_data[value_4[11:8]] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h1C ) ? char_data[value_4[ 7:4]] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h1D ) ? char_data[value_4[ 3:0]] :
							( char_y[6:0] == 7'h1D && char_x[6:0] == 7'h1B ) ? char_data[value_5[11:8]] :
							( char_y[6:0] == 7'h1D && char_x[6:0] == 7'h1C ) ? char_data[value_5[ 7:4]] :
							( char_y[6:0] == 7'h1D && char_x[6:0] == 7'h1D ) ? char_data[value_5[ 3:0]] : 0;
					
	// dump binary		
	logic bin_str;
	assign bin_str = ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h20 ) ? char_data[{3'b000,value_1[11]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h21 ) ? char_data[{3'b000,value_1[10]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h22 ) ? char_data[{3'b000,value_1[09]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h23 ) ? char_data[{3'b000,value_1[08]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h24 ) ? char_data[{3'b000,value_1[07]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h25 ) ? char_data[{3'b000,value_1[06]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h26 ) ? char_data[{3'b000,value_1[05]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h27 ) ? char_data[{3'b000,value_1[04]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h28 ) ? char_data[{3'b000,value_1[03]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h29 ) ? char_data[{3'b000,value_1[02]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h2A ) ? char_data[{3'b000,value_1[01]}] :
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h2B ) ? char_data[{3'b000,value_1[00]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h20 ) ? char_data[{3'b000,value_2[11]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h21 ) ? char_data[{3'b000,value_2[10]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h22 ) ? char_data[{3'b000,value_2[09]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h23 ) ? char_data[{3'b000,value_2[08]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h24 ) ? char_data[{3'b000,value_2[07]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h25 ) ? char_data[{3'b000,value_2[06]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h26 ) ? char_data[{3'b000,value_2[05]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h27 ) ? char_data[{3'b000,value_2[04]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h28 ) ? char_data[{3'b000,value_2[03]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h29 ) ? char_data[{3'b000,value_2[02]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h2A ) ? char_data[{3'b000,value_2[01]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h2B ) ? char_data[{3'b000,value_2[00]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h20 ) ? char_data[{3'b000,value_3[11]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h21 ) ? char_data[{3'b000,value_3[10]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h22 ) ? char_data[{3'b000,value_3[09]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h23 ) ? char_data[{3'b000,value_3[08]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h24 ) ? char_data[{3'b000,value_3[07]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h25 ) ? char_data[{3'b000,value_3[06]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h26 ) ? char_data[{3'b000,value_3[05]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h27 ) ? char_data[{3'b000,value_3[04]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h28 ) ? char_data[{3'b000,value_3[03]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h29 ) ? char_data[{3'b000,value_3[02]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h2A ) ? char_data[{3'b000,value_3[01]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h2B ) ? char_data[{3'b000,value_3[00]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h20 ) ? char_data[{3'b000,value_4[11]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h21 ) ? char_data[{3'b000,value_4[10]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h22 ) ? char_data[{3'b000,value_4[09]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h23 ) ? char_data[{3'b000,value_4[08]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h24 ) ? char_data[{3'b000,value_4[07]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h25 ) ? char_data[{3'b000,value_4[06]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h26 ) ? char_data[{3'b000,value_4[05]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h27 ) ? char_data[{3'b000,value_4[04]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h28 ) ? char_data[{3'b000,value_4[03]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h29 ) ? char_data[{3'b000,value_4[02]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h2A ) ? char_data[{3'b000,value_4[01]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h2B ) ? char_data[{3'b000,value_4[00]}] : 
						  // diag
						  ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h16 ) ? char_data[{3'b000,diag_reg[03]}] :
						  ( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h16 ) ? char_data[{3'b000,diag_reg[02]}] :
						  ( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h16 ) ? char_data[{3'b000,diag_reg[01]}] :
						  ( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h16 ) ? char_data[{3'b000,diag_reg[00]}] :  0;
	
	// video encoder
	video_encoder _encode
	(
		.clk( clk     ),
		.clk5( clk5   ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.red	( red   | {8{char_bit}} | {8{hex_str | bin_str}} | scope_red   ),
		.green( green | {8{char_bit}} | {8{hex_str | bin_str}} | scope_green ),
		.blue	( blue  | {8{char_bit}} | {8{hex_str | bin_str}} | scope_blue  ),
		.hdmi_data( hdmi_data )
	);
	
endmodule // VIDEO

////////////////////////////////////////////
///////        VIDEO 2
////////////////////////////////////////////
module video2
(
	input	clk,
	input clk5,
	input reset,
	output [7:0] hdmi_data,
	// AXI sram read port connection
	input  logic 			psram_ready,
	input  logic [17:0] 	rdata,
	input  logic 			rvalid,
	output logic [24:0] 	araddr,
	output logic 			arvalid, 
	input  logic 			arready,
	input  logic			mem_clk
);
	
	logic [7:0] red, green, blue;
	logic blank, hsync, vsync;
	
	// sych generator
	vga_800x480_sync _sync
	(
		.clk(   clk   ),	
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync )
	);
	
	// Font Generator
	logic [7:0] char_x, char_y;
	logic [15:0] char_data;
	
	ascii_font57 _font
	(
		.clk( clk ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.char_x( char_x ), // 0 to 105 chars horizontally
		.char_y( char_y ), // o to 59 rows vertically
		//.char_data( char_data )
		.hex_char( char_data ),
		.ascii_char( )	
		);
	
	
		// Display something
	logic char_bit;
	assign char_bit = ( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h12 ) ? char_data['h1] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h13 ) ? char_data['h2] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h14 ) ? char_data['h3] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h15 ) ? char_data['h4] :
							( char_y[6:1] == 6'h5 && char_x[6:0] == 7'h16 ) ? char_data['h5] : 0;
	

	// Tie off read port
	// 4ch Oscilloscope mem & vga display
	
	logic [7:0] scope_red, scope_green, scope_blue;
	vga_wave_display _scope(
		.clk(   clk ),
		.reset( reset ),
		// video sync 
		.blank( blank ), 
		.hsync( hsync ),
		.vsync( vsync ),
		// AXI Sram Read port connection
		.psram_ready	( psram_ready 	 ) ,
		.rdata			( rdata 			 ) , 
		.rvalid			( rvalid		    ) ,
		.araddr			( araddr[24:0]	 ) ,
		.arvalid			( arvalid		 ) , 
		.arready			( arready		 ) ,
		.mem_clk			( mem_clk ),
		// video output
		.red(   scope_red ),
		.green( scope_green ),
		.blue(  scope_blue )	
	);	
	
	// video encoder
	video_encoder _encode
	(
		.clk( clk     ),
		.clk5( clk5   ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.red	( {8{char_bit}} | scope_red   ),
		.green( {8{char_bit}} | scope_green ),
		.blue	( {8{char_bit}} | scope_blue  ),
		.hdmi_data( hdmi_data )
	);
	
endmodule // Video 2