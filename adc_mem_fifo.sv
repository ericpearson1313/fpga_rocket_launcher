
module adc_mem_fifo 
#(parameter DATA_WIDTH=16, 
  parameter ADDR_WIDTH=9, 
  parameter DATA_WORDS=512 )
(
    clk, reset,
    full, empty, we, re, d, q,
	 almost_empty
);
    input       clk;
    input       reset;
    output      full, empty;
	 output		 almost_empty;
    input       we, re;
    output  [DATA_WIDTH-1:0]  q;
    input   [DATA_WIDTH-1:0]  d;
    
    reg  [ADDR_WIDTH-1:0]   rcnt, wcnt;
    reg  [ADDR_WIDTH:0]     depth;
    reg  [1:0]              state; 
    reg  [DATA_WIDTH-1:0]   oreg, rwreg;
    reg                     rwflag;
    wire [DATA_WIDTH-1:0]   ram_q;
    wire [ADDR_WIDTH-1:0]   rcnt_plus1; 
    wire [ADDR_WIDTH-1:0]   raddr;
    
	 assign almost_empty = ( depth < 8 ) ? 1'b1 : 1'b0;
    assign empty = (depth == 0) ? 1'b1 : 1'b0;
    assign full  = (depth >= DATA_WORDS-3) ? 1'b1 : 1'b0;
    assign q = ( state[0] ) ? oreg : ( rwflag ) ? rwreg : ram_q; // select oreg if its holding data
    assign rcnt_plus1 = rcnt + 1;
    assign raddr = ( |state ) ? rcnt_plus1 : rcnt;
    
    always @(posedge clk) begin
        if( reset ) begin
            rcnt <= 0;
            wcnt <= 0;
            depth <= 0;
            state <= 2'b00;
            oreg  <= 0;
            rwreg <= 0;
            rwflag <= 0;
        end else begin
            // Depth Counter
            if( we && !re ) begin
                depth <= depth + 1;
            end else if( !we && re ) begin
                depth <= depth - 1;
            end
            // State
            state[1] <= ( state[1] &  state[0] ) |  we | 
                        ( state[1] & !state[0] & (depth > 1) );
            state[0] <= ( state[1] |  state[0] ) & !re;
            // Wcnt
            if( we ) begin
                wcnt <= wcnt + 1;
            end
            // rcnt
            if( re ) begin
                rcnt <= rcnt_plus1;
            end
            // oreg - load if empty, or if full and is read
            if( state == 2'b10 && !re || 
                state == 2'b11 &&  re  ) begin
                oreg <= ( rwflag ) ? rwreg : ram_q;
            end
            // rw collision
            rwflag <= ( (raddr == wcnt) && we ) ? 1'b1 : 1'b0;
            rwreg  <= d;
        end
    end

//	sram512x16 _fifo_mem (
//		.clock(		clk),
//		.data(		),
//		.rdaddress(	rd_addr),
//		.wraddress(	wr_addr),
//		.wren(		we),
//		.q(			ram_q));
    
    generic_sram2p #(DATA_WIDTH, ADDR_WIDTH, DATA_WORDS) mem
    (
	   .dout 	    (ram_q),
	   .clk		    (clk),
	   .wen		    (we),
      .ren         (1'b1),
	   .waddr	    (wcnt ),
	   .raddr	    (raddr),
	   .din 		    (d)
	);
endmodule

module generic_sram2p
#(parameter DATA_WIDTH=16, 
  parameter ADDR_WIDTH=9, 
  parameter DATA_WORDS=512 )
( dout, clk, wen, waddr, raddr, din, ren );
  output [DATA_WIDTH-1:0] 	dout;
  input   			clk;          
  input   			wen;           
  input   			ren;           
  input   [ADDR_WIDTH-1:0]	waddr;         
  input   [ADDR_WIDTH-1:0]	raddr;         
  input   [DATA_WIDTH-1:0] din;           

  reg [DATA_WIDTH-1:0] data_reg;
  reg [DATA_WIDTH-1:0] mem [DATA_WORDS-1:0];
  always @(posedge clk)
	begin
		if(wen)
			mem[waddr]<= din;
		data_reg <= mem[raddr];
	end
	assign dout = data_reg;
endmodule