// 5x7 font display engine
module font57
(
	input clk,
	input reset,
	input blank,
	input hsync,
	input vsync,
	output [6:0] char_x,
	output [6:0] char_y,
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
