
///////////////////////////////////
//////
//////   VGA SCROLLING SCOPE DISPLAY
//////
/////////////////////////////////


module vga_scope
// Scrolling scope with 60Hz capure rate (in Vsync)
// Includes min/max on each signal ast full rate (glitch capture)
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	input [7:0] char_x,
	input [7:0] char_y,
	input [255:0] ascii_char,
   input [15:0] hex_char,
	input [1:0] bin_char,
	input [11:0] ad_a0,
	input [11:0] ad_a1,
	input [11:0] ad_b0,
	input [11:0] ad_b1,
	input ad_strobe,
	input ad_clk,
	output [7:0] red,
	output [7:0] green,
	output [7:0] blue
);

// sram write upon vsync 

	logic [9:0] rd_addr, wr_addr;
	logic [7:0] a0, a1, b0, b1;
	logic we;
	logic vsync_d1;
	logic blank_d1;
	logic [9:0] xcnt, ycnt;
	
	
	// AD CLK based state machine, gets Min,Max and latches at rising vsync.
	logic [3:0] vsync_del;
	logic [11:0] ad_a0_min_cur, ad_a0_max_cur;
	logic [11:0] ad_a1_min_cur, ad_a1_max_cur;
	logic [11:0] ad_b0_min_cur, ad_b0_max_cur;
	logic [11:0] ad_b1_min_cur, ad_b1_max_cur;
	logic [11:0] ad_a0_min, ad_a0_max;
	logic [11:0] ad_a1_min, ad_a1_max;
	logic [11:0] ad_b0_min, ad_b0_max;
	logic [11:0] ad_b1_min, ad_b1_max;	
	always @(posedge ad_clk) begin
		if( ad_strobe ) begin
			vsync_del[3:0] <= { vsync_del[2:0], vsync };
			if( vsync_del[2] & !vsync_del[3] ) begin // rising edge of vsync
				// star a new cycle based on current sample
				ad_a0_min_cur <= ad_a0;
				ad_a0_max_cur <= ad_a0;
				ad_a1_min_cur <= ad_a1;
				ad_a1_max_cur <= ad_a1;
				ad_b0_min_cur <= ad_b0;
				ad_b0_max_cur <= ad_b0;
				ad_b1_min_cur <= ad_b1;
				ad_b1_max_cur <= ad_b1;
				// capture and hold the mins/maxes 
				// will be picked up on falling vsync edge
				ad_a0_min <= ad_a0_min_cur;
				ad_a0_max <= ad_a0_max_cur;
				ad_a1_min <= ad_a1_min_cur;
				ad_a1_max <= ad_a1_max_cur;
				ad_b0_min <= ad_b0_min_cur;
				ad_b0_max <= ad_b0_max_cur;
				ad_b1_min <= ad_b1_min_cur;
				ad_b1_max <= ad_b1_max_cur;
			end else begin // on the other data cycles
				// Update mins/maxes
				ad_a0_min_cur <= ( ad_a0_min_cur[11:0] > ad_a0[11:0] ) ? ad_a0 : ad_a0_min_cur ;
				ad_a0_max_cur <= ( ad_a0_max_cur[11:0] < ad_a0[11:0] ) ? ad_a0 : ad_a0_max_cur ;
				ad_a1_min_cur <= ( ad_a1_min_cur[11:0] > ad_a1[11:0] ) ? ad_a1 : ad_a1_min_cur ;
				ad_a1_max_cur <= ( ad_a1_max_cur[11:0] < ad_a1[11:0] ) ? ad_a1 : ad_a1_max_cur ;
				ad_b0_min_cur <= ( ad_b0_min_cur[11:0] > ad_b0[11:0] ) ? ad_b0 : ad_b0_min_cur ;
				ad_b0_max_cur <= ( ad_b0_max_cur[11:0] < ad_b0[11:0] ) ? ad_b0 : ad_b0_max_cur ;
				ad_b1_min_cur <= ( ad_b1_min_cur[11:0] > ad_b1[11:0] ) ? ad_b1 : ad_b1_min_cur ;
				ad_b1_max_cur <= ( ad_b1_max_cur[11:0] < ad_b1[11:0] ) ? ad_b1 : ad_b1_max_cur ;
				// Hold frame value;
				ad_a0_min <= ad_a0_min;
				ad_a0_max <= ad_a0_max;
				ad_a1_min <= ad_a1_min;
				ad_a1_max <= ad_a1_max;
				ad_b0_min <= ad_b0_min;
				ad_b0_max <= ad_b0_max;
				ad_b1_min <= ad_b1_min;
				ad_b1_max <= ad_b1_max;
			end
		end else begin // non same cycles, just hold everything
			vsync_del <= vsync_del;
			// Update mins/maxes
			ad_a0_min_cur <= ad_a0_min_cur;
			ad_a0_max_cur <= ad_a0_max_cur;
			ad_a1_min_cur <= ad_a1_min_cur;
			ad_a1_max_cur <= ad_a1_max_cur;
			ad_b0_min_cur <= ad_b0_min_cur;
			ad_b0_max_cur <= ad_b0_max_cur;
			ad_b1_min_cur <= ad_b1_min_cur;
			ad_b1_max_cur <= ad_b1_max_cur;
			// Hold frame value;
			ad_a0_min <= ad_a0_min;
			ad_a0_max <= ad_a0_max;
			ad_a1_min <= ad_a1_min;
			ad_a1_max <= ad_a1_max;
			ad_b0_min <= ad_b0_min;
			ad_b0_max <= ad_b0_max;
			ad_b1_min <= ad_b1_min;
			ad_b1_max <= ad_b1_max;
		end
	end
		
	// Capture Buffer Write COntrol 
	
	always @(posedge clk) begin
		if ( reset ) begin
			we <= 0;
			wr_addr <= 800 - 1;
			vsync_d1 <= 0;
		end else begin
			vsync_d1 <= vsync;
			we <= ( !vsync && vsync_d1 ) ? 1'b1 : 1'b0; // vsync falling
			wr_addr <= ( !vsync && vsync_d1 ) ? wr_addr + 1 : wr_addr ; // wrap
		end
	end	

	// sram read with horzonal pixel counter, which starts with wr_addr - 639
		
	always @(posedge clk) begin
		if ( reset ) begin
			xcnt <= 0;
			ycnt <= 0;
			rd_addr <= 0;
			blank_d1 <= 0;
		end else begin
			blank_d1 <= blank;
			xcnt <= ( blank ) ? 0 : xcnt + 1;
			ycnt <= ( vsync ) ? 0 : 
					  ( blank && !blank_d1 ) ? ycnt + 1 : ycnt;
			rd_addr <= wr_addr - 799 + xcnt;
		end
	end

	// Srams to hold the data

	logic [7:0] a0_min, a0_max;
	logic [7:0] a1_min, a1_max;
	logic [7:0] b0_min, b0_max;
	logic [7:0] b1_min, b1_max;	
	
	
	generic_sram2p #(64, 10, 1024 ) _mem
    (
	   .dout 	    ( { a0_max,a1_max,b0_max,b1_max,a0_min,a1_min,b0_min,b1_min } ),
		.clk		    (clk),
	   .wen		    (we),
      .ren         (1'b1),
	   .waddr	    (wr_addr),
	   .raddr	    (rd_addr),
	   .din 		    ({ad_a0_max[11:4],
		               ad_a1_max[11:4],
		               ad_b0_max[11:4],
		               ad_b1_max[11:4],
		               ad_a0_min[11:4],
		               ad_a1_min[11:4],
		               ad_b0_min[11:4],
		               ad_b1_min[11:4] } )
	);	
	
	// Display Logic rd_data vs ycnt to give veritcal axis
	// Scope screen is 256 rows on bottom 480 line display and takes the full 800 width. 
	// The four channels will be different colors.
	// if heights off bottom matches value, turn on the pel.
	
	logic pel_gd, pel_a0, pel_a1, pel_b0, pel_b1;

	
	always @(posedge clk) begin
		if ( reset ) begin
				pel_gd <= 0;
				pel_a0 <= 0;
				pel_a1 <= 0;
				pel_b1 <= 0;
				pel_b0 <= 0;
		end else begin
			if( ycnt >= 224 ) begin
				pel_gd <= ( xcnt[5:0] == 6'd63 || ycnt[4:0] == 5'd0 ) ? 1'b1 : 1'b0; // a grid
//				pel_a0 <= ( a0 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
//				pel_a1 <= ( a1 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
//				pel_b0 <= ( b0 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
//				pel_b1 <= ( b1 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_a0 <= ( a0_max >= (ycnt - 224) && a0_min <= (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_a1 <= ( a1_max >= (ycnt - 256) && a1_min <= (ycnt - 256) ) ? 1'b1 : 1'b0; 
				pel_b0 <= ( b0_max >= (ycnt - 288) && b0_min <= (ycnt - 288) ) ? 1'b1 : 1'b0; 
				pel_b1 <= ( b1_max >= (ycnt - 320) && b1_min <= (ycnt - 320) ) ? 1'b1 : 1'b0; 
			end else begin
				pel_gd <= 0;
				pel_a0 <= 0;
				pel_a1 <= 0;
				pel_b1 <= 0;
				pel_b0 <= 0;
			end
		end
	end	
	
	// Color Legend
	logic a0_str, a1_str, b0_str, b1_str;
	string_overlay #(.LEN(2)) _a0_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h18),.y('h15), .out( a0_str), .str("A0") );
	string_overlay #(.LEN(2)) _a1_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h18),.y('h17), .out( a1_str), .str("A1") );
	string_overlay #(.LEN(2)) _b0_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h18),.y('h19), .out( b0_str), .str("B0") );
	string_overlay #(.LEN(2)) _b1_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h18),.y('h1B), .out( b1_str), .str("B1") );

	
	// colors: and priority a0 white, a1 red, b0 green, b1 blue, grid grey
	assign { red, green, blue } = 
					( pel_a0 | a0_str ) ? 24'hFFFFFF :
					( pel_a1 | a1_str ) ? 24'hff0000 :
					( pel_b0 | b0_str ) ? 24'h00ff00 :
					( pel_b1 | b1_str ) ? 24'h0000ff :
					( pel_gd ) ? 24'h808080 : 24'h000000;
endmodule

///////////////////////////////////
//////
//////   TINY SCOPE DISPLAY
//////
/////////////////////////////////


module tiny_scope
// Scrolling scope with 60Hz/n capture rate (in Vsync)
// Includes min/max on each signal at full rate (glitch capture!)
// Vertical scale = 1/2, takes 96 pels of height 
// 6x gridlines, offset, horizontal, 64/N ~ 1sec
// Vertical offset and horizontal start/stop parameterized
#(
	parameter V_START	= 240;//459 - 96,
	parameter V_HEIGHT= 192;//96; // supported 96 at 1/2 vert scale, or 192 for full 1:1 vert scale
	parameter H_START = 450, // Starting pel horizontally
	parameter H_END 	= 750, // Last pel horizontally
	parameter N 		= 3, // how many 60Hz frames to accumulate 
	parameter GD_COLOR= 24'h32006a, /* smpte_deep_violet */
	parameter BG_COLOR= 24'h1d1d1d /* smpte_eerie_black */
	)
	
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	input [11:0] ad_a0,
	input [11:0] ad_a1,
	input [11:0] ad_b0,
	input [11:0] ad_b1,
	input ad_strobe,
	input ad_clk,
	input halt,
	output [7:0] red,
	output [7:0] green,
	output [7:0] blue
);

// sram write upon vsync 

	logic [8:0] rd_addr, wr_addr;
	logic [7:0] a0, a1, b0, b1;
	logic we;
	logic vsync_d1;
	logic blank_d1;
	logic [9:0] xcnt, ycnt;
	
	
	// AD CLK based state machine, gets Min,Max and latches at rising vsync.
	// Counter to accumulate over N vsync's
	logic [3:0] vsync_cnt;
	logic [5:0] sec_cnt; // 60 ticks/sec
	logic [3:0] vsync_del;
	logic [11:0] ad_a0_min_cur, ad_a0_max_cur;
	logic [11:0] ad_a1_min_cur, ad_a1_max_cur;
	logic [11:0] ad_b0_min_cur, ad_b0_max_cur;
	logic [11:0] ad_b1_min_cur, ad_b1_max_cur;
	logic [11:0] ad_a0_min, ad_a0_max;
	logic [11:0] ad_a1_min, ad_a1_max;
	logic [11:0] ad_b0_min, ad_b0_max;
	logic [11:0] ad_b1_min, ad_b1_max;	
	logic gd_mark, gd_mark_cur;
	always @(posedge ad_clk) begin
		if( ad_strobe ) begin
			vsync_del[3:0] <= { vsync_del[2:0], vsync };
			vsync_cnt <= ( !vsync_del[2] & vsync_del[3] ) ? ( vsync_cnt == N - 1 ) ? 0 : vsync_cnt + 1 : vsync_cnt; // count on falling
			sec_cnt   <= ( !vsync_del[2] & vsync_del[3] ) ? (   sec_cnt == 59    ) ? 0 :   sec_cnt + 1 : sec_cnt;   // count to 60 falling
			if( vsync_del[2] & !vsync_del[3] & vsync_cnt == 0 ) begin // rising edge of Nth vsync
				// star a new cycle based on current sample
				ad_a0_min_cur <= ad_a0;
				ad_a0_max_cur <= ad_a0;
				ad_a1_min_cur <= ad_a1;
				ad_a1_max_cur <= ad_a1;
				ad_b0_min_cur <= ad_b0;
				ad_b0_max_cur <= ad_b0;
				ad_b1_min_cur <= ad_b1;
				ad_b1_max_cur <= ad_b1;
				gd_mark_cur   <= ( sec_cnt == 0 ) ? 1'b1 : 1'b0;
				// capture and hold the mins/maxes 
				// will be picked up on falling vsync edge
				ad_a0_min <= ad_a0_min_cur;
				ad_a0_max <= ad_a0_max_cur;
				ad_a1_min <= ad_a1_min_cur;
				ad_a1_max <= ad_a1_max_cur;
				ad_b0_min <= ad_b0_min_cur;
				ad_b0_max <= ad_b0_max_cur;
				ad_b1_min <= ad_b1_min_cur;
				ad_b1_max <= ad_b1_max_cur;
				gd_mark   <= gd_mark_cur;
			end else begin // on the other data cycles
				// Update mins/maxes
				ad_a0_min_cur <= ( ad_a0_min_cur[11:0] > ad_a0[11:0] ) ? ad_a0 : ad_a0_min_cur ;
				ad_a0_max_cur <= ( ad_a0_max_cur[11:0] < ad_a0[11:0] ) ? ad_a0 : ad_a0_max_cur ;
				ad_a1_min_cur <= ( ad_a1_min_cur[11:0] > ad_a1[11:0] ) ? ad_a1 : ad_a1_min_cur ;
				ad_a1_max_cur <= ( ad_a1_max_cur[11:0] < ad_a1[11:0] ) ? ad_a1 : ad_a1_max_cur ;
				ad_b0_min_cur <= ( ad_b0_min_cur[11:0] > ad_b0[11:0] ) ? ad_b0 : ad_b0_min_cur ;
				ad_b0_max_cur <= ( ad_b0_max_cur[11:0] < ad_b0[11:0] ) ? ad_b0 : ad_b0_max_cur ;
				ad_b1_min_cur <= ( ad_b1_min_cur[11:0] > ad_b1[11:0] ) ? ad_b1 : ad_b1_min_cur ;
				ad_b1_max_cur <= ( ad_b1_max_cur[11:0] < ad_b1[11:0] ) ? ad_b1 : ad_b1_max_cur ;
				gd_mark_cur   <= ( sec_cnt == 0 ) ? 1'b1 : gd_mark_cur; // Capture if a sec tick occured
				// Hold frame value;
				ad_a0_min <= ad_a0_min;
				ad_a0_max <= ad_a0_max;
				ad_a1_min <= ad_a1_min;
				ad_a1_max <= ad_a1_max;
				ad_b0_min <= ad_b0_min;
				ad_b0_max <= ad_b0_max;
				ad_b1_min <= ad_b1_min;
				ad_b1_max <= ad_b1_max;
				gd_mark   <= gd_mark;
			end
		end else begin // non same cycles, just hold everything
			vsync_cnt <= vsync_cnt;
			vsync_del <= vsync_del;
			// Update mins/maxes
			ad_a0_min_cur <= ad_a0_min_cur;
			ad_a0_max_cur <= ad_a0_max_cur;
			ad_a1_min_cur <= ad_a1_min_cur;
			ad_a1_max_cur <= ad_a1_max_cur;
			ad_b0_min_cur <= ad_b0_min_cur;
			ad_b0_max_cur <= ad_b0_max_cur;
			ad_b1_min_cur <= ad_b1_min_cur;
			ad_b1_max_cur <= ad_b1_max_cur;
			gd_mark_cur   <= gd_mark_cur;
			// Hold frame value;
			ad_a0_min <= ad_a0_min;
			ad_a0_max <= ad_a0_max;
			ad_a1_min <= ad_a1_min;
			ad_a1_max <= ad_a1_max;
			ad_b0_min <= ad_b0_min;
			ad_b0_max <= ad_b0_max;
			ad_b1_min <= ad_b1_min;
			ad_b1_max <= ad_b1_max;
			gd_mark   <= gd_mark;
		end
	end
		
	// Capture Buffer Write COntrol 
	
	always @(posedge clk) begin
		if ( reset ) begin
			we <= 0;
			wr_addr <= H_END - H_START; // Start at right edge aligned
			vsync_d1 <= 0;
		end else begin
			vsync_d1 <= vsync;
			if( halt ) begin
				we <= 0;
				wr_addr <= wr_addr;
			end else begin
				we <= ( !vsync && vsync_d1 && vsync_cnt == 0 ) ? 1'b1 : 1'b0; // vsync falling
				wr_addr <= ( !vsync && vsync_d1 && vsync_cnt == 0 ) ? wr_addr + 1 : wr_addr ; // wrap
			end
		end
	end	

	// sram read with horzonal pixel counter, which starts with wr_addr - 639
		
	always @(posedge clk) begin
		if ( reset ) begin
			xcnt <= 0;
			ycnt <= 0;
			rd_addr <= 0;
			blank_d1 <= 0;
		end else begin
			blank_d1 <= blank;
			xcnt <= ( blank ) ? 0 : xcnt + 1;
			ycnt <= ( vsync ) ? 0 : 
					  ( blank && !blank_d1 ) ? ycnt + 1 : ycnt;
			rd_addr <= wr_addr - (H_END - H_START) + xcnt - H_START;
		end
	end

	// Srams to hold the data

	logic [7:0] a0_min, a0_max;
	logic [7:0] a1_min, a1_max;
	logic [7:0] b0_min, b0_max;
	logic [7:0] b1_min, b1_max;	
	logic vgrid;

    generic_sram2p #(65, 9, 512 ) _mem
    (
	   .dout 	    ( { a0_max,a1_max,b0_max,b1_max,a0_min,a1_min,b0_min,b1_min,vgrid } ),
		.clk		    (clk),
	   .wen		    (we),
      .ren         (1'b1),
	   .waddr	    (wr_addr),
	   .raddr	    (rd_addr),
	   .din 		    ({ad_a0_max[11:4],
		               ad_a1_max[11:4],
		               ad_b0_max[11:4],
		               ad_b1_max[11:4],
		               ad_a0_min[11:4],
		               ad_a1_min[11:4],
		               ad_b0_min[11:4],
		               ad_b1_min[11:4],
		               gd_mark           } )
	);	
	
	// Display Logic rd_data vs ycnt to give veritcal axis
	// Scope screen is 256 rows on bottom 480 line display and takes the full 800 width. 
	// The four channels will be different colors.
	// if heights off bottom matches value, turn on the pel.
	
	logic pel_gd, pel_a0, pel_a1, pel_b0, pel_b1, pel_bg;
	
	always @(posedge clk) begin
		if ( reset ) begin
				pel_bg <= 0;
				pel_gd <= 0;
				pel_a0 <= 0;
				pel_a1 <= 0;
				pel_b1 <= 0;
				pel_b0 <= 0;
		end else begin
			if( ycnt >= V_START && ycnt < V_START + V_HEIGHT &&
			    xcnt >= H_START && xcnt <= H_END ) begin
				pel_bg <= ( xcnt >= H_START && xcnt <= H_END ) ? 1'b1 : 1'b0;
				if( V_HEIGHT == 96 ) begin // 96 is 1/2 height
					pel_gd <= ( vgrid  || ((ycnt-V_START)&15)==8 ) ? 1'b1 : 1'b0; // a grid
					pel_a0 <= ( a0_max[7:1] >= (ycnt - (V_START - 24)) && a0_min[7:1] <= (ycnt - (V_START - 24)) ) ? 1'b1 : 1'b0; 
					pel_a1 <= ( a1_max[7:1] >= (ycnt - (V_START -  8)) && a1_min[7:1] <= (ycnt - (V_START -  8)) ) ? 1'b1 : 1'b0; 
					pel_b0 <= ( b0_max[7:1] >= (ycnt - (V_START +  8)) && b0_min[7:1] <= (ycnt - (V_START +  8)) ) ? 1'b1 : 1'b0; 
					pel_b1 <= ( b1_max[7:1] >= (ycnt - (V_START + 24)) && b1_min[7:1] <= (ycnt - (V_START + 24)) ) ? 1'b1 : 1'b0; 
				end else begin // assume 192 full scale 
					pel_gd <= ( vgrid  || ((ycnt-V_START)&31)==16 ) ? 1'b1 : 1'b0; // a grid
					pel_a0 <= ( a0_max[7:0] >= (ycnt - (V_START - 48)) && a0_min[7:0] <= (ycnt - (V_START - 48)) ) ? 1'b1 : 1'b0; 
					pel_a1 <= ( a1_max[7:0] >= (ycnt - (V_START - 16)) && a1_min[7:0] <= (ycnt - (V_START - 16)) ) ? 1'b1 : 1'b0; 
					pel_b0 <= ( b0_max[7:0] >= (ycnt - (V_START + 16)) && b0_min[7:0] <= (ycnt - (V_START + 16)) ) ? 1'b1 : 1'b0; 
					pel_b1 <= ( b1_max[7:0] >= (ycnt - (V_START + 48)) && b1_min[7:0] <= (ycnt - (V_START + 48)) ) ? 1'b1 : 1'b0; 
				end
			end else begin
				pel_bg <= 0;
				pel_gd <= 0;
				pel_a0 <= 0;
				pel_a1 <= 0;
				pel_b1 <= 0;
				pel_b0 <= 0;
			end
		end
	end	
	
	// colors: and priority a0 white, a1 red, b0 green, b1 blue, grid grey
	assign { red, green, blue } = 
					( pel_a0 ) ? 24'hFFFFFF :
					( pel_a1 ) ? 24'hff0000 :
					( pel_b0 ) ? 24'h00ff00 :
					( pel_b1 ) ? 24'h0000ff :
					( pel_gd ) ? GD_COLOR   : 
					( pel_bg ) ? BG_COLOR   : 
									 24'h000000 ;
endmodule



///////////////////////////////////
//////
//////   VGA WAVEFORM DISPLAY
//////
/////////////////////////////////

module vga_wave_display
// Displays waveforms from a large capture buffer (4M samples)
// During Vsync it reads 800 bursts of 16byte-samples from the big buffer and copies to display buffer 
// for wave displays.
// ultimately keypad controlled pan/zoom will determine the read address and pitch.
(
	input clk,
	input reset,
	// Sync input
	input blank,
	input hsync,
	input vsync,
	// Font input
	input [255:0] ascii_char,
	input [15:0] hex_char,
	input [1:0] bin_char,
	input [7:0] char_x,
	input [7:0] char_y,
	// RGB output
	output [7:0] red,
	output [7:0] green,
	output [7:0] blue,
	// AXI sram read port connection
	input  logic 			psram_ready,
	input  logic [17:0] 	rdata,
	input  logic 			rvalid,
	output logic [24:0] 	araddr,
	output logic 			arvalid, 
	input  logic 			arready,
	input	 logic			mem_clk
);

// sram write upon vsync 

	logic [9:0] rd_addr, wr_addr;
	logic [7:0] a0, a1, b0, b1;
	logic [3:0] we;
	logic [3:0] vsync_d;
	logic blank_d1;
	logic [9:0] xcnt, ycnt;

	// PSRAM Read Access
	// During Vsync do 800 read bursts
	// Data will be written to display waveform ram
	// Handshake the addresses via: araddr[24:0], arvalid, arready;
	// should not start until psram is ready.
	
		typedef enum {
      STATE_STARTUP,	// wait for psram_ready
		STATE_VSYNC, // wait for vsync start
		STATE_ARVALID, // Wait for Ready
		STATE_INC // Increment the counter
	} State;
		
	State state = STATE_STARTUP;
	
	logic [9:0] read_cnt; // count burst to generate address
	always @(posedge mem_clk) begin
		if( reset || !psram_ready ) begin
			state <= STATE_STARTUP;
			read_cnt <= 0;
		end else begin
			case( state ) 
			STATE_STARTUP : begin
				state <= ( psram_ready ) ? STATE_VSYNC : STATE_STARTUP ;
				read_cnt <= 0;
				end
			STATE_VSYNC   : begin
				read_cnt <= 0;
				state <= ( vsync_d[2] && !vsync_d[3] ) ? STATE_ARVALID : STATE_VSYNC;
				end
			STATE_ARVALID : begin
				read_cnt <= read_cnt; 
				state <= ( arvalid && arready ) ? STATE_INC : STATE_ARVALID ;
				end
			STATE_INC : begin
				read_cnt <= read_cnt + 1;
				state <= ( read_cnt == 799 ) ? STATE_VSYNC : STATE_ARVALID ;	
				end
			default       : begin
				state <= STATE_STARTUP;
				read_cnt <= 0;
				end
			endcase 
		end
	end
	
	assign arvalid = ( state == STATE_ARVALID ) ? 1'b1 : 1'b0;
	assign araddr[24:0] = { 12'h000, read_cnt[9:0], 3'b000 };
	//assign araddr[24:0] = { read_cnt[9:0], 15'd0 };
	
	
	// Capture Buffer Write COntrol (MEM_CLK) 
	// whenever a read burst occurs it is 4 cycles long.
	// 800 transfers done each vsync.
	// Address increments by 1 for each of 4 reads.
	
	logic [2:0] rvalid_del;
	always @(posedge mem_clk) begin
		rvalid_del[2:0] <= { rvalid_del[1:0], rvalid };
		vsync_d <= { vsync_d[2:0], vsync };
		wr_addr <= ( vsync_d[2] && !vsync_d[3] ) ? 0 : // clear on vsync rising edge
		           ( we[3]              ) ? wr_addr + 1 : wr_addr; // inc +1 for each burst
	end
	// write generation from rvalid burst
	assign we[0] = ( rvalid_del[2:0] == 3'b000 && rvalid ) ? 1'b1 :1'b0;
	assign we[1] = ( rvalid_del[2:0] == 3'b001 && rvalid ) ? 1'b1 :1'b0;
	assign we[2] = ( rvalid_del[2:0] == 3'b011 && rvalid ) ? 1'b1 :1'b0;
	assign we[3] = ( rvalid_del[2:0] == 3'b111 && rvalid ) ? 1'b1 :1'b0;

	
	// Video Buffer Read address generation (in sync with video)
	// sram read with horzonal pixel counter
		
	always @(posedge clk) begin
		if ( reset ) begin
			xcnt <= 0;
			ycnt <= 0;
			rd_addr <= 0;
			blank_d1 <= 0;
		end else begin
			blank_d1 <= blank;
			xcnt <= ( blank ) ? 0 : xcnt + 1;
			ycnt <= ( vsync ) ? 0 : 
					  ( blank && !blank_d1 ) ? ycnt + 1 : ycnt;
			rd_addr <= xcnt;
		end
	end

	// Srams to hold the data

	logic [17:0] q0, q1, q2, q3;
	logic [17:0] rdata_d1, rdata_d2, rdata_d3;
	reg [71:0] mem [799:0];
		
	// Write ports
	always @(posedge mem_clk) begin
		if( we[0] ) rdata_d3 <= rdata;
		if( we[1] ) rdata_d2 <= rdata;
		if( we[2] ) rdata_d1 <= rdata;
		if( we[3] ) mem[wr_addr] <= { rdata[17:0], rdata_d1[17:0], rdata_d2[17:0], rdata_d3[17:0] };
	end
	
	// Read Ports
	always @( posedge clk) begin
		{ q3,  q2, q1, q0 } <= mem[ rd_addr ];
	end
	

	// Display Logic rd_data vs ycnt to give veritcal axis
	// Scope screen is 256 rows on bottom 480 line display and takes the full 800 width. 
	// The four channels will be different colors.
	// if heights off bottom matches value, turn on the pel.

	logic pel_gd, pel_a0, pel_a01, pel_a1, pel_a2, pel_b0, pel_b01, pel_b1, pel_b2, pel_es, pel_pw, pel_bn, pel_fr;
	always @(posedge clk) begin
		if ( reset ) begin
				pel_gd <= 0;
				pel_a0 <= 0;
				pel_a01<= 0;
				pel_a1 <= 0;
				pel_a2 <= 0;
				pel_b1 <= 0;
				pel_b2 <= 0;
				pel_b0 <= 0;
				pel_b01<= 0;
				pel_es <= 0;
				pel_pw <= 0;
				pel_bn <= 0;
				pel_fr <= 0;
		end else begin
			if( ycnt >= 32 && ycnt <= ( 15 * 32 ) ) begin
				pel_gd <= ( xcnt[5:0] == 6'd63 || ycnt[4:0] == 5'd0 ) ? 1'b1 : 1'b0; // a grid
				pel_a0 <= ( { 1'b0, q0[12:9], q0[7:4] } == ({1'b0,ycnt} -  32) ) ? 1'b1 : 1'b0; 
				pel_a01<= ( { 1'b0, q0[12  ], q0[6:0] } == ({1'b0,ycnt} - 224) ) ? 1'b1 : 1'b0; // 16x A0
				pel_a1 <= ( { 1'b0, q1[12:9], q1[7:4] } == ({1'b0,ycnt} -  64) ) ? 1'b1 : 1'b0; 
				pel_a2 <= ( { 1'b0, q1[12  ], q1[6:0] } == ({1'b0,ycnt} -  0 ) ) ? 1'b1 : 1'b0; // 16x A1
				pel_b0 <= ( { 1'b0, q2[12:9], q2[7:4] } == ({1'b0,ycnt} -  96) ) ? 1'b1 : 1'b0; 
				pel_b01<= ( { 1'b0, q2[12  ], q2[6:0] } == ({1'b0,ycnt} - 256) ) ? 1'b1 : 1'b0; // 16x B0
				pel_b1 <= ( { 1'b0, q3[12:9], q3[7:4] } == ({1'b0,ycnt} - 128) ) ? 1'b1 : 1'b0; 
				pel_b2 <= ( { 1'b0, q3[12],   q3[6:0] } == ({1'b0,ycnt} - 192) ) ? 1'b1 : 1'b0; // 16x b1
				pel_es <= ( { 1'b0,q0[16:13],q1[16:13]} == ({1'b0,ycnt} - 160) ) ? 1'b1 : 1'b0; 
				pel_pw <= ( (  q3[13] && ycnt[9:4] == 'd25  ) ||
			               ( !q3[13] && ycnt[9:0] == 'd415 ) ) ? 1'b1 : 1'b0;
				pel_bn <= ( (  q3[14] && ycnt[9:4] == 'd27  ) ||
				            ( !q3[14] && ycnt[9:0] == 'd447 ) ) ? 1'b1 : 1'b0;
				pel_fr <= ( (  q3[15] && ycnt[9:4] == 'd29  ) ||
				            ( !q3[15] && ycnt[9:0] == 'd479 ) ) ? 1'b1 : 1'b0;
			end else begin
				pel_gd <= 0;
				pel_a0 <= 0;
				pel_a01<= 0;
				pel_a1 <= 0;
				pel_b1 <= 0;
				pel_b2 <= 0;
				pel_b0 <= 0;
				pel_b01<= 0;
				pel_es <= 0;
				pel_pw <= 0;
				pel_bn <= 0;
				pel_fr <= 0;
			end
		end
	end	
	
	
	// Color Legend Strings
	logic est_str, pwm_str, tit_str, bn_str, fr_str;
	logic a0_str, a1_str, a2_str, b0_str, b1_str, b2_str, a01_str, b01_str;
	logic hor_str, ho2_str;
	//string_overlay #(.LEN(50)) _title   (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h01), .out(tit_str), .str("3MHZ 4CH 12BIT 4MSample TRACE BUFFER, 800x480 XVGA") );	
	//string_overlay #(.LEN(19)) _a0_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h12), .out( a0_str), .str(" A0 OutI  2.5A/div ") );
	//string_overlay #(.LEN(19)) _a1_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h16), .out( a1_str), .str(" A1 CapV  100V/div ") );
	//string_overlay #(.LEN(19)) _b0_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h1A), .out( b0_str), .str(" B0 CapI  2.5A/div ") );
	//string_overlay #(.LEN(19)) _b1_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h1E), .out( b1_str), .str(" B1 OutV  100V/div ") );
	//string_overlay #(.LEN(19)) _est_str (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h22), .out(est_str), .str("Est OutI  2.5A/div ") );
	//string_overlay #(.LEN( 3)) _pwm_str (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h03),.y('h32), .out(pwm_str), .str("PWM") );
	//string_overlay #(.LEN( 4)) _bn_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h03),.y('h36), .out( bn_str), .str("BURN") );
	//string_overlay #(.LEN( 4)) _fr_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h03),.y('h3A), .out( fr_str), .str("FIRE") );
	//string_overlay #(.LEN(19)) _b2_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h26), .out( b2_str), .str(" B1 OutV* 6.4V/div ") );
	//string_overlay #(.LEN(19)) _a2_str  (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h0E), .out( a2_str), .str(" A1 CapV* 6.4V/div ") );
	//string_overlay #(.LEN(19)) _a01_str (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h2A), .out(a01_str), .str(" A0 OutI* 150mA/div") );
	//string_overlay #(.LEN(19)) _b01_str (.clk(clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h2e), .out(b01_str), .str(" B0 CapI* 150mA/div") );

	
	// colors: and priority a0 white, a1 red, b0 green, b1 blue, grid grey
	assign { red, green, blue } = 
					( tit_str| hor_str | ho2_str ) ? 24'hFFFFFF : // Title text
					( pel_a0 | a0_str  ) ? 24'hFFFFFF :
					( pel_a01|a01_str  ) ? 24'h00c0c0 :
					( pel_a1 | a1_str  ) ? 24'hff0000 :
					( pel_a2 | a2_str  ) ? 24'hf00000 :			
					( pel_b0 | b0_str  ) ? 24'h00ff00 :
					( pel_b01|b01_str  ) ? 24'h00c000 :
					( pel_b1 | b1_str  ) ? 24'h0000ff :
					( pel_b2 | b2_str  ) ? 24'h0000c0 :
					( pel_es | est_str ) ? 24'hc0c0c0 :
					( pel_pw | pwm_str ) ? 24'hc0c000 :		
					( pel_bn | bn_str  ) ? 24'hc0c000 :		
					( pel_fr | fr_str  ) ? 24'hc0c000 :				
					( pel_gd           ) ? 24'h32006a : 24'h000000;
	
endmodule