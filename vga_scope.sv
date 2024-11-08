module vga_scope
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
	
	
	always @(posedge clk) begin
		if ( reset ) begin
			we <= 0;
			wr_addr <= 640 - 1;
			vsync_d1 <= 0;
		end else begin
			vsync_d1 <= vsync;
			we <= ( vsync && !vsync_d1 ) ? 1'b1 : 1'b0;
			wr_addr <= ( vsync && !vsync_d1 ) ? wr_addr + 1 : wr_addr ; // wrap
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

	sram1024x8 _a0_mem (.clock(clk),.data(ad_a0[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(a0));
	sram1024x8 _a1_mem (.clock(clk),.data(ad_a1[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(a1));
	sram1024x8 _b0_mem (.clock(clk),.data(ad_b0[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(b0));
	sram1024x8 _b1_mem (.clock(clk),.data(ad_b1[10:3]),.rdaddress(rd_addr),.wraddress(wr_addr),.wren(we),.q(b1));
	
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
				pel_a0 <= ( a0 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_a1 <= ( a1 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_b0 <= ( b0 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
				pel_b1 <= ( b1 == (ycnt - 224) ) ? 1'b1 : 1'b0; 
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