


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
		if( reset ) begin
			shift_d0[9:0] <= 0;
			shift_d1[9:0] <= 0;
			shift_d2[9:0] <= 0;
			shift_ck[9:0] <= 0;
		end else begin
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
		( barcnt == 4'h0 ) ? 24'hc0c0c0 /* smpte_argent */ :
		( barcnt == 4'h1 ) ? 24'hc0c000 /* smpte_acid_green */ :
		( barcnt == 4'h2 ) ? 24'h00c000 /* smpte_islamic_green */ :
		( barcnt == 4'h3 ) ? 24'h00c0c0 /* smpte_turquoise_surf */ :
		( barcnt == 4'h4 ) ? 24'hc000c0 /* smpte_deep_mageneta */ :
		( barcnt == 4'h5 ) ? 24'hc00000 /* smpte_ue_red */ :
		( barcnt == 4'h6 ) ? 24'h0000c0 /* smpte_medium_blud */ :
		( barcnt == 4'h7 ) ? 24'h131313 /* smpte_chinese_black */ :
		( barcnt == 4'h8 ) ? 24'h00214c /* smpte_oxford_blue */ :
		( barcnt == 4'h9 ) ? 24'hffffff /* smpte_white */ :
		( barcnt == 4'ha ) ? 24'h32006a /* smpte_deep_violet */ :
		( barcnt == 4'hb ) ? 24'h090909 /* smpte_vampire_black */ :
		( barcnt == 4'hc ) ? 24'h1d1d1d /* smpte_eerie_black */ : 
		                     24'h000000 /*  */ ;
											
//assign red   = {xcnt[6],{7{ycnt[5]}}};
//assign green = {xcnt[7],{7{ycnt[6]}}};
//assign blue  = {xcnt[8],{7{ycnt[7]}}};

endmodule // test_pattern