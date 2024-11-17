// Controller PSRAM with SPI8 interface.
// Starts us and allows access to a 32 Mbyte sram. (16M x 16)

module psram_ctrl(
		// System
		
		input clk,
		input clk4,
		input reset,

		// Psram spi8 interface
		// Run on Clk4. Wire up to pads (registered)
		output [7:0] 	spi_data_out,
		output   		spi_data_oe,
		output [1:0]   	spi_le_out, // match delay
		input  [7:0] 	spi_data_in,
		input  [1:0]	spi_le_in, // match IO registering
		output			spi_clk,
		output			spi_cs,
		output			spi_rwds_out,
		output			spi_rwds_oe,
		input			spi_rwds_in,

		// Status
		output			psram_ready,	// Indicates control is ready to accept requests
		output [31:0]	dev_id,			// Should be should be 32'h0E96_0001
		
		// AXI4 R/W port
		// Write Data
		input	[15:0]	wdata,
		input			wvalid,	// assumed 1, non blocking, data is available
		output			wready,
		// Write Addr
		input	[24:0]	awaddr,
		input	[7:0]	awlen,	// assumed 8
		input			awvalid, 
		output			awready,
		// Write Response
		input			bready,	// Assume 1, non blocking
		output			bvalid,
		output	[1:0]	bresp,
		// Read Addr
		input	[24:0]	araddr,
		input	[7:0] 	arlen,	// assumed 4
		input			arvalid,	
		output			arready,
		// Read Data
		output [15:0]	rdata,
		output 			rvalid,
		input			rready // Assumed 1, non blocking
		);
	
	// Store clocked commands;
	logic [4:0][0:8][0:24][15:0] cmds;
	
	
	// Commands
	parameter CRESET = 0;
	parameter CRDID7 = 1;
	parameter CWRLAT = 2;
	parameter CRDMEM = 3;
	parameter CWRMEM = 4;
	// Wave Index
	parameter ICLK = 0; // Clock generation
	parameter ICS  = 1; // Chip select generation (note inversion
	parameter IDOE = 2; // Data Bus output enable
	parameter IDQH = 3; // Input write data (high mibble)
	parameter IDQL = 4; // Input write data (low mibble)
	parameter ILE =  5; // { LE1, LE0 } latch enable signals for propagation
	parameter ISOE = 6; // { RWDS, OE } for rwds signal
	parameter ILST = 7; // Last 
	parameter IRDY = 8; // Input write data ready signal
   
   //                                | Reset_En        | Soft Reset and then delay
	//                                | CMD    | CS     | CMD    |
	//                                | 0      | 1      | 2      |
	assign cmds[CRESET][ICLK][0:02] = {16'h0110,16'h0000,16'h0110};
	assign cmds[CRESET][ICS ][0:02] = {16'h1111,16'h0000,16'h1111};
	assign cmds[CRESET][IDOE][0:02] = {16'h1111,16'h0000,16'h1111};
	assign cmds[CRESET][IDQH][0:02] = {16'h6666,16'h0000,16'h9999};
	assign cmds[CRESET][IDQL][0:02] = {16'h6666,16'h0000,16'h9999};
	assign cmds[CRESET][ILE ][0:02] = 0;
	assign cmds[CRESET][ISOE][0:02] = 0;
	assign cmds[CRESET][ILST][0:02] = {16'h0000,16'h0000,16'h1111};
	assign cmds[CRESET][IRDY][0:02] = 0;
	
    //                                | Read ID Lat=7
	//                                | CMD    | A0     | A1     | L1     | L2     | L3     | L4     | L5     | L6     | L7     | L1     | L2     | L3     | L4     | L5     | L6     | L7     | ID0    | ID1    | del    |
	//                                | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      | 8      | 9      | 10     | 11     | 12     | 13     | 14     | 15     | 16     | 17     | 18     | 19     |
	assign cmds[CRDID7][ICLK][0:19] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0000};
	assign cmds[CRDID7][ICS ][0:19] = {16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000};
	assign cmds[CRDID7][IDOE][0:19] = {16'h1111,16'h1111,16'h1111,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
	assign cmds[CRDID7][IDQH][0:19] = {16'h9999,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
	assign cmds[CRDID7][IDQL][0:19] = {16'hFFFF,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
	assign cmds[CRDID7][ILE ][0:19] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0010,16'h2010,16'h2000};
	assign cmds[CRDID7][ISOE][0:19] = 0;
	assign cmds[CRDID7][ILST][0:19] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
	assign cmds[CRDID7][IRDY][0:19] = 0;
		
	//                                | WriteEn|        | Write CR0 = 8FEF to give LAT=3
	//                                | CMD    | CS     | CMD    | A0     | A1     | CR     
	//                                | 0      | 1      | 2      | 3      | 4      | 5      
	assign cmds[CWRLAT][ICLK][0:05] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110};
	assign cmds[CWRLAT][ICS ][0:05] = {16'h1111,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111};
	assign cmds[CWRLAT][IDOE][0:05] = {16'h1111,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111};
	assign cmds[CWRLAT][IDQH][0:05] = {16'h0000,16'h0000,16'h7777,16'h0000,16'h0000,16'h88EE};
	assign cmds[CWRLAT][IDQL][0:05] = {16'h6666,16'h0000,16'h1111,16'h0000,16'h0000,16'hFFFF};
	assign cmds[CWRLAT][ILE ][0:05] = 0;
	assign cmds[CWRLAT][ISOE][0:05] = 0;
	assign cmds[CWRLAT][ILST][0:05] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
    assign cmds[CWRLAT][IRDY][0:05] = 0;

	logic [7:0][3:0] ar   = { 7'h00, araddr[24:3], 3'b000 };  // 8 byte aligned read address
	logic [15:0] arh0 = { ar[7], ar[7], ar[5], ar[5] };
	logic [15:0] arl0 = { ar[6], ar[6], ar[4], ar[4] };
	logic [15:0] arh1 = { ar[3], ar[3], ar[1], ar[1] };
	logic [15:0] arl1 = { ar[2], ar[2], ar[0], ar[0] };
	

	//                                | Read Mem, BL=8
	//                                | CMD    | A0     | A1     | L1     | L2     | L3     | L1     | L2     | L3     | R0     | R1     | R2     | R3     | del   |
	//                                | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      | 8      | 9      | 10     | 11     | 12     | 13     |
	assign cmds[CRDMEM][ICLK][0:13] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0000};
	assign cmds[CRDMEM][ICS ][0:13] = {16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000};
	assign cmds[CRDMEM][IDOE][0:13] = {16'h1111,16'h1111,16'h1111,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
	assign cmds[CRDMEM][IDQH][0:13] = {16'hEEEE, arh0   , arh1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
	assign cmds[CRDMEM][IDQL][0:13] = {16'hEEEE, arl0   , arl1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
	assign cmds[CRDMEM][ILE ][0:13] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0010,16'h2010,16'h2010,16'h2010,16'h2000};
	assign cmds[CRDMEM][ISOE][0:13] = 0;
	assign cmds[CRDMEM][ILST][0:13] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
    assign cmds[CRDMEM][IRDY][0:13] = 0;
	

	logic [7:0][3:0] aw   = { 7'h00, awaddr[24:4], 4'b0000 };  // 16 byte aligned write address	
	logic [15:0] awh0 = { aw[7], aw[7], aw[5], aw[5] };
	logic [15:0] awl0 = { aw[6], aw[6], aw[4], aw[4] };
	logic [15:0] awh1 = { aw[3], aw[3], aw[1], aw[1] };
	logic [15:0] awl1 = { aw[2], aw[2], aw[0], aw[0] };

	
	logic [15:0] d = wdata;
	logic [15:0] dh = { {2{d[15:12]}}, {2{d[7:4]}} };
	logic [15:0] dl = { {2{d[11: 8]}}, {2{d[3:0]}} };
	
	//                                | Write Mem, BL=16
	//                                | CMD    | A0     | A1     | L1     | L2     | L3     | L1     | L2     | L3     | W0     | W1     | W2     | W3     | W4     | W5     | W6     | W7     |
	//                                | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      | 8      | 9      | 10     | 11     | 12     | 13     | 14     | 15     | 16     |
	assign cmds[CWRMEM][ICLK][0:13] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110};
	assign cmds[CWRMEM][ICS ][0:13] = {16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111};
	assign cmds[CWRMEM][IDOE][0:13] = {16'h1111,16'h1111,16'h1111,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111};
	assign cmds[CWRMEM][IDQH][0:13] = {16'hDDDD, awh0   , awh1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,  dh    ,  dh    ,  dh    ,  dh    ,  dh    ,  dh    ,  dh    ,  dh    };
	assign cmds[CWRMEM][IDQL][0:13] = {16'hEEEE, awl0   , awl1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,  dl    ,  dl    ,  dl    ,  dl    ,  dl    ,  dl    ,  dl    ,  dl    };
	assign cmds[CWRMEM][ILE ][0:13] = 0;
	assign cmds[CWRMEM][ISOE][0:13] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111};
	assign cmds[CWRMEM][ILST][0:13] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
	assign cmds[CWRMEM][IRDY][0:13] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000};

	
	logic lastq; // registered flag for last.
	
	/////////////////////////////////
	// State Machine
	/////////////////////////////////
	
	typedef enum {
      STATE_IDLE,		// Reset
      STATE_STARTUP,	// wait 150us
		STATE_CMD_RESET, STATE_CMD_RESET_WAIT,
		STATE_CMD_RESET_DELAY, STATE_CMD_RESET_DELAY_WAIT,
		STATE_READY,
		STATE_CMD_RDID7, STATE_CMD_RDID7_WAIT,
		STATE_CMD_WRLAT, STATE_CMD_WRLAT_WAIT,
		STATE_CMD_RDMEM, STATE_CMD_RDMEM_WAIT,
		STATE_CMD_WRMEM, STATE_CMD_WRMEM_WAIT   
	} State;
		
	State state;		
	State next_state;
	
   always_comb begin
      if(reset) begin
         next_state = STATE_IDLE;
      end else begin
         case(state)
				STATE_IDLE : 			next_state = STATE_STARTUP;
				// wait for 150 Usec after reset/power up.
				STATE_STARTUP : 		next_state = ( delay == 0 ) ? STATE_CMD_RESET : STATE_STARTUP;
				// Reset Enable and reset
				STATE_CMD_RESET :		next_state = STATE_CMD_RESET_WAIT;
				STATE_CMD_RESET_WAIT :	next_state = ( lastq ) ? STATE_CMD_RESET_DELAY : STATE_CMD_RESET_WAIT;
				// 400 Ns, 20 cycles after reset.
				STATE_CMD_RESET_DELAY : next_state = STATE_CMD_RESET_DELAY_WAIT;
				STATE_CMD_RESET_DELAY_WAIT : next_state = ( delay == 0 ) ? STATE_CMD_RDID7 : STATE_CMD_RESET_DELAY_WAIT ;
				// Read ID lat = 7
				STATE_CMD_RDID7 : 		next_state = STATE_CMD_RDID7_WAIT ;
				STATE_CMD_RDID7_WAIT :	next_state = ( lastq ) ? STATE_CMD_WRLAT : STATE_CMD_RDID7_WAIT ;
				// Write CR0 lat=3
				STATE_CMD_WRLAT :		next_state = STATE_CMD_WRLAT_WAIT ;
				STATE_CMD_WRLAT_WAIT :	next_state = ( lastq ) ? STATE_READY : STATE_CMD_WRLAT_WAIT ;
				// Ready for command, recieve and dispatch
				STATE_READY        :	next_state = 	( arvalid ) ? 	STATE_CMD_RDMEM :
														( awvalid ) ? 	STATE_CMD_WRMEM : STATE_READY ;
				// Read Mem burst
				STATE_CMD_RDMEM : 		next_state = STATE_CMD_RDMEM_WAIT;
				STATE_CMD_RDMEM_WAIT :	next_state = ( lastq ) ? STATE_READY : STATE_CMD_RDMEM_WAIT ;
				// Write Mem burst
				STATE_CMD_WRMEM : 		next_state = STATE_CMD_WRMEM_WAIT ;
				STATE_CMD_WRMEM_WAIT :  next_state = ( lastq ) ? STATE_READY : STATE_CMD_WRMEM_WAIT ;
				default				 :	next_state = STATE_IDLE;
         endcase
      end
   end

   always @(posedge clk) begin
      state <= next_state;
	end
	
	logic [12:0] delay;
	always @(posedge clk) begin
		if( reset ) begin
			delay <= 13'd7200; // 150usec with 48 Mhz clk
		end else if ( state == STATE_IDLE ) begin
			delay <= 13'd7200; // 150usec with 48 Mhz clk
		end else if ( state == STATE_CMD_RESET_DELAY ) begin
			delay <= 13'd20; // 400 nSec on 48Mhz clk
		end else if ( delay == 0 ) begin
			delay <= 0;
		end else begin
			delay <= delay - 1;
		end
	end


/////////////////////
//  Read Data Latch
/////////////////////

	
		logic [1:0] le_inreg;
		logic [8:0] data_inreg;
		logic [8:0] data_le0_reg;
		logic [17:0] data_le1_reg;
		logic [3:0] delay_le1;
		
		always @(posedge clk4) begin
			// register LE and data inputs 
			le_inreg <= spi_le_in;
			data_inreg <= { spi_rwds_in, spi_data_in }; // 9 bits of data, rwds, data[7:0]
			// Latch data
			data_le0_reg <= ( le_inreg[0] ) ? data_inreg : data_le0_reg;
			data_le1_reg <= ( le_inreg[1] ) ? { data_le0_reg, data_inreg } : data_le1_reg;
			// LE1 delay chain
			delay_le1[3:0] <= { |delay_le1[2:0] | le_inreg[1], delay_le1[1:0], le_inreg[1] };
		end
		
		// AXI Read Data Port
		
		always @(posedge clk) begin
			rdata  <= ( delay_le1[3] ) ? data_le1_reg : rdata;
			rvalid <=   delay_le1[3];
		end

	
endmodule
	