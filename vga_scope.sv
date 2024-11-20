module vga_scope
// Scrolling scope with 60Hz capure rate (in Vsync)
// Includes min/max on each signal ast full rate (glitch capture)
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
				ad_a0_min_cur <= ( ad_a0_min_cur[10:0] > ad_a0[10:0] ) ? ad_a0 : ad_a0_min_cur ;
				ad_a0_max_cur <= ( ad_a0_max_cur[10:0] < ad_a0[10:0] ) ? ad_a0 : ad_a0_max_cur ;
				ad_a1_min_cur <= ( ad_a1_min_cur[10:0] > ad_a1[10:0] ) ? ad_a1 : ad_a1_min_cur ;
				ad_a1_max_cur <= ( ad_a1_max_cur[10:0] < ad_a1[10:0] ) ? ad_a1 : ad_a1_max_cur ;
				ad_b0_min_cur <= ( ad_b0_min_cur[10:0] > ad_b0[10:0] ) ? ad_b0 : ad_b0_min_cur ;
				ad_b0_max_cur <= ( ad_b0_max_cur[10:0] < ad_b0[10:0] ) ? ad_b0 : ad_b0_max_cur ;
				ad_b1_min_cur <= ( ad_b1_min_cur[10:0] > ad_b1[10:0] ) ? ad_b1 : ad_b1_min_cur ;
				ad_b1_max_cur <= ( ad_b1_max_cur[10:0] < ad_b1[10:0] ) ? ad_b1 : ad_b1_max_cur ;
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
			wr_addr <= 640 - 1;
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
			rd_addr <= wr_addr - 639 + xcnt;
		end
	end

	// Srams to hold the data

	logic [7:0] a0_min, a0_max;
	logic [7:0] a1_min, a1_max;
	logic [7:0] b0_min, b0_max;
	logic [7:0] b1_min, b1_max;	
	
	sram1024x8 _a0_mem_max (.clock(clk),.data(ad_a0_max[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(a0_max));
	sram1024x8 _a1_mem_max (.clock(clk),.data(ad_a1_max[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(a1_max));
	sram1024x8 _b0_mem_max (.clock(clk),.data(ad_b0_max[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(b0_max));
	sram1024x8 _b1_mem_max (.clock(clk),.data(ad_b1_max[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(b1_max));
	sram1024x8 _a0_mem_min (.clock(clk),.data(ad_a0_min[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(a0_min));
	sram1024x8 _a1_mem_min (.clock(clk),.data(ad_a1_min[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(a1_min));
	sram1024x8 _b0_mem_min (.clock(clk),.data(ad_b0_min[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(b0_min));
	sram1024x8 _b1_mem_min (.clock(clk),.data(ad_b1_min[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(b1_min));
	
	// Display Logic rd_data vs ycnt to give veritcal axis
	// Scope screen is 256 rows on bottom 480 line display and takes the full 640 width. 
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
				pel_a1 <= ( a1_max >= (ycnt - 224) && a1_min <= (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_b0 <= ( b0_max >= (ycnt - 224) && b0_min <= (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_b1 <= ( b1_max >= (ycnt - 224) && b1_min <= (ycnt - 224) ) ? 1'b1 : 1'b0; 
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
	logic [6:0] char_x, char_y;
	logic [15:0] char_data;
	logic char_bit;
	
	font57 _font
	(
		.clk( clk ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.char_x( char_x ), // 0 to 105 chars horizontally
		.char_y( char_y ), // o to 59 rows vertically
		.char_data( char_data )
	);
	
	assign char_bit = ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h18 ) ? char_data['hA] :
							( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h19 ) ? char_data['h0] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h18 ) ? char_data['hA] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h19 ) ? char_data['h1] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h18 ) ? char_data['hB] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h19 ) ? char_data['h0] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h18 ) ? char_data['hB] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h19 ) ? char_data['h1] : 0;
	
	// colors: and priority a0 white, a1 red, b0 green, b1 blue, grid grey
	assign { red, green, blue } = 
					( pel_a0 ) ? 24'hFFFFFF :
					( pel_a1 ) ? 24'hff0000 :
					( pel_b0 ) ? 24'h00ff00 :
					( pel_b1 ) ? 24'h0000ff :
					( pel_gd ) ? 24'h808080 : 
					( char_bit && char_y[2:1] == 2'b10 ) ? 24'hFFFFFF :
					( char_bit && char_y[2:1] == 2'b11 ) ? 24'hff0000 :
					( char_bit && char_y[2:1] == 2'b00 ) ? 24'h00ff00 :
					( char_bit && char_y[2:1] == 2'b01 ) ? 24'h0000ff : 24'h000000;
	
endmodule



///////////////////////////////////
//////
//////   VGA WAVE DISPLAY
//////
/////////////////////////////////

module vga_wave_display
// Displays waveforms from a large capture buffer (4M samples)
// During Vsync it reads 640 bursts of 16byte-samples from the big buffer and copies to display buffer 
// for wave displays.
// ultimately keypad controlled pan/zoom will determine the read address and pitch.
(
	input clk,
	input reset,
	// Sync input
	input blank,
	input hsync,
	input vsync,
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
	// During Vsync do 640 read bursts
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
				state <= ( read_cnt == 639 ) ? STATE_VSYNC : STATE_ARVALID ;	
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
		
	// Capture Buffer Write COntrol (MEM_CLK) 
	// whenever a read burst occurs it is 4 cycles long.
	// 640 transfers done each vsync.
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
	
	sram1024x9_2clk _mem0_0 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[17:9]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[0]),.q(q0[17:9]));
	sram1024x9_2clk _mem0_1 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[ 8:0]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[0]),.q(q0[ 8:0]));
	sram1024x9_2clk _mem1_0 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[17:9]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[1]),.q(q1[17:9]));
	sram1024x9_2clk _mem1_1 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[ 8:0]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[1]),.q(q1[ 8:0]));
	sram1024x9_2clk _mem2_0 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[17:9]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[2]),.q(q2[17:9]));
	sram1024x9_2clk _mem2_1 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[ 8:0]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[2]),.q(q2[ 8:0]));
	sram1024x9_2clk _mem3_0 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[17:9]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[3]),.q(q3[17:9]));
	sram1024x9_2clk _mem3_1 (.wrclock(mem_clk),.rdclock(clk),.data(rdata[ 8:0]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we[3]),.q(q3[ 8:0]));
	
	// Display Logic rd_data vs ycnt to give veritcal axis
	// Scope screen is 256 rows on bottom 480 line display and takes the full 640 width. 
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
			if( ycnt >= 128 && ycnt <= 384 ) begin
				pel_gd <= ( xcnt[5:0] == 6'd63 || ycnt[4:0] == 5'd0 ) ? 1'b1 : 1'b0; // a grid
				pel_a0 <= ( { q0[12:9], q0[7:4] } == (ycnt - 128) ) ? 1'b1 : 1'b0; 
				pel_a1 <= ( { q1[12:9], q1[7:4] } == (ycnt - 128) ) ? 1'b1 : 1'b0; 
				pel_b0 <= ( { q2[12:9], q2[7:4] } == (ycnt - 128) ) ? 1'b1 : 1'b0; 
				pel_b1 <= ( { q3[12:9], q3[7:4] } == (ycnt - 128) ) ? 1'b1 : 1'b0; 
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
	logic [6:0] char_x, char_y;
	logic [15:0] char_data;
	logic char_bit;
	
	font57 _font
	(
		.clk( clk ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.char_x( char_x ), // 0 to 105 chars horizontally
		.char_y( char_y ), // o to 59 rows vertically
		.char_data( char_data )
	);
	
	assign char_bit = ( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h18 ) ? char_data['hA] :
							( char_y[6:0] == 7'h15 && char_x[6:0] == 7'h19 ) ? char_data['h0] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h18 ) ? char_data['hA] :
							( char_y[6:0] == 7'h17 && char_x[6:0] == 7'h19 ) ? char_data['h1] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h18 ) ? char_data['hB] :
							( char_y[6:0] == 7'h19 && char_x[6:0] == 7'h19 ) ? char_data['h0] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h18 ) ? char_data['hB] :
							( char_y[6:0] == 7'h1B && char_x[6:0] == 7'h19 ) ? char_data['h1] : 0;
	
	// colors: and priority a0 white, a1 red, b0 green, b1 blue, grid grey
	assign { red, green, blue } = 
					( pel_a0 ) ? 24'hFFFFFF :
					( pel_a1 ) ? 24'hff0000 :
					( pel_b0 ) ? 24'h00ff00 :
					( pel_b1 ) ? 24'h0000ff :
					( pel_gd ) ? 24'h808080 : 
					( char_bit && char_y[2:1] == 2'b10 ) ? 24'hFFFFFF :
					( char_bit && char_y[2:1] == 2'b11 ) ? 24'hff0000 :
					( char_bit && char_y[2:1] == 2'b00 ) ? 24'h00ff00 :
					( char_bit && char_y[2:1] == 2'b01 ) ? 24'h0000ff : 24'h000000;
	
endmodule