
module video
(

// Video Pixel Clock
input clk // pixel clock
// Outputs



);
endmodule

module TDMS_encoder 
// translated from VHDL orginally by MikeField <hamster@snap.net.nz>
// re-written to closer match DVI-1.0 spec
(
	input clk,        // pixel rate clock
	input [7:0] data, // raw 8 bit video
	input [1:0] c, 	// control bits {c1,c0}
	input blank,      // !den == video blanking
	output encoded[9:0] // encoded pixel
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
		encoded <=  ( c[1:0] == 2'b00 ) ? 10'b0010101011 :
						( c[1:0] == 2'b01 ) ? 10'b1101010100 :
						( c[1:0] == 2'b10 ) ? 10'b0010101010 : 
					   /*c[1:0] == 2'b11*/   10'b1101010101 ;
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

endmodule // video_encoder

module vga_sync
// Generate a video sync
(
	// Clock
	input clk,	// Pixel clk
	input reset,
	
	// Video Sync Interface, pix clock sync
	output blank,
	output hsync,
	output vsync
);

endmodule // vga_sync

module test_pattern
// Create a test patern
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
logic hsync_d1;

always @(posedge clk) begin
	hsync_d1 <= hsync;
	if ( reset ) begin
		xcnt <= 0;
		ycnt <= 0;
	end else begin
		if( hsync_d1 && !hsync ) begin // hsync cycle
			xcnt <= 0;
			ycnt <= ( vsync ) ? 0 : ycnt + 1;
		end else begin
			xcnt <= xcnt + 1; // X pos
		end
	end
end

// Color outputs a function of location

assign red   = {8{xcnt[5]}};
assign green = {8{xcnt[6]}};
assign blue  = {8{xcnt[7]}};

endmodule // test_pattern