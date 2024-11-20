// Controller PSRAM with SPI8 interface.
// Starts us and allows access to a 32 Mbyte sram. (16M x 16)

module psram_ctrl(
		// System
		
		input  logic	clk,
		input  logic 	clk4,
		input  logic	reset,

		// Psram spi8 interface
		// Run on Clk4. Wire up to pads (registered)
		output logic [7:0] 	spi_data_out,
		output logic   		spi_data_oe,
		output logic [1:0]   spi_le_out, // match delay
		input  logic [7:0] 	spi_data_in,
		input  logic [1:0]	spi_le_in, // match IO registering
		output logic 			spi_clk,
		output logic 			spi_cs,
		output logic 			spi_rwds_out,
		output logic 			spi_rwds_oe,
		input	 logic 			spi_rwds_in,

		// Status
		output logic			psram_ready,	// Indicates control is ready to accept requests
		
		// AXI4 R/W port
		// Write Data
		input	 logic [15:0]	wdata,
		input	 logic 			wvalid,	// assumed 1, non blocking, data is available
		output logic 			wready,
		// Write Addr
		input	 logic [24:0]	awaddr,
		input	 logic [7:0]	awlen,	// assumed 8
		input	 logic 			awvalid, 
		output logic 			awready,
		// Write Response
		input	 logic 			bready,	// Assume 1, non blocking
		output logic			bvalid,
		output logic	[1:0]	bresp,
		// Read Addr
		input	 logic [24:0]	araddr,
		input	 logic [7:0] 	arlen,	// assumed 4
		input	 logic 			arvalid,	
		output logic 			arready,
		// Read Data
		output logic [17:0]	rdata,   // {2{ rwds, data[7:0}}}
		output logic 			rvalid,
		input	 logic 		   rready // Assumed 1, non blocking
		);
	
	// Store clocked commands;
	//     CMD  SIG State phase Nib  (input)
	logic [0:4][0:8][0:24][0:3][3:0] cmds;
	// Command shift registers
	//     CMD State
	logic [0:4][0:24] cmd_sreg, cmd_sreg_d;
	
	// Anded command reg and command bits, ready for Reduction OR
	//     SIG   Nib phase CMD State   (output)
	logic  [0:8][3:0][0:3][0:4][0:24] gated_cmds;
	logic  [0:8][3:0][0:3]            cmds_reg;
	logic  [0:8][3:0]						 cmds_x4;
	
	// AXI address registers
	logic [24:0] awaddr_reg;
	logic [24:0] araddr_reg;
	
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
	
	// Re-arrange Read address for command insertion
	logic [7:0][3:0] ar;  // 8 byte aligned read address
	logic [15:0] arh0, arl0, arh1, arl1;
	assign ar   = { 7'h00, araddr_reg[24:3], 3'b000 };  // 8 byte aligned read address
	assign arh0 = { ar[7], ar[7], ar[5], ar[5] };
	assign arl0 = { ar[6], ar[6], ar[4], ar[4] };
	assign arh1 = { ar[3], ar[3], ar[1], ar[1] };
	assign arl1 = { ar[2], ar[2], ar[0], ar[0] };
	
	// Re-arrange write address for command insertion
	logic [7:0][3:0] aw;
	logic [15:0] awh0, awl0, awh1, awl1;
	assign aw   = { 7'h00, awaddr_reg[24:4], 4'b0000 };  // 16 byte aligned write address	
	assign awh0 = { aw[7], aw[7], aw[5], aw[5] };
	assign awl0 = { aw[6], aw[6], aw[4], aw[4] };
	assign awh1 = { aw[3], aw[3], aw[1], aw[1] };
	assign awl1 = { aw[2], aw[2], aw[0], aw[0] };	
	
	// Re-arrange write data for command insertion
	logic [15:0] d, dh, dl;
	assign d = wdata;
	assign dh = { {2{d[15:12]}}, {2{d[7:4]}} };
	assign dl = { {2{d[11: 8]}}, {2{d[3:0]}} };   
	
	///////////////////////
	/// Command Chains
	///////////////////////
	
	always_comb begin : _command_decode
		// default inputs to zero
		cmds = 0; 
		//   						      | Reset_En        | Soft Reset and then delay
		//   RESET   	            | CMD    | CS     | CMD    |
		//                         | 0      | 1      | 2      |
		cmds[CRESET][ICLK][0:02] = {16'h0110,16'h0000,16'h0110};
		cmds[CRESET][ICS ][0:02] = {16'h1111,16'h0000,16'h1111};
		cmds[CRESET][IDOE][0:02] = {16'h1111,16'h0000,16'h1111};
		cmds[CRESET][IDQH][0:02] = {16'h6666,16'h0000,16'h9999};
		cmds[CRESET][IDQL][0:02] = {16'h6666,16'h0000,16'h9999};
		cmds[CRESET][ILE ][0:02] = 0;
		cmds[CRESET][ISOE][0:02] = 0;
		cmds[CRESET][ILST][0:02] = {16'h0000,16'h0000,16'h1111};
		cmds[CRESET][IRDY][0:02] = 0;
		//                         | Read ID Lat=7
		//   READ ID	            | CMD    | A0     | A1     | L1     | L2     | L3     | L4     | L5     | L6     | L7     | L1     | L2     | L3     | L4     | L5     | L6     | L7     | Extra  | ID0    | ID1    | del    |
		//                         | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      | 8      | 9      | 10     | 11     | 12     | 13     | 14     | 15     | 16     | 17     | 18     | 19     | 20     |
		cmds[CRDID7][ICLK][0:20] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0000};
		cmds[CRDID7][ICS ][0:20] = {16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000};
		cmds[CRDID7][IDOE][0:20] = {16'h1111,16'h1111,16'h1111,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
		cmds[CRDID7][IDQH][0:20] = {16'h9999,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
		cmds[CRDID7][IDQL][0:20] = {16'hFFFF,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
		cmds[CRDID7][ILE ][0:20] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0010,16'h2010,16'h2000};
		cmds[CRDID7][ISOE][0:20] = 0;
		cmds[CRDID7][ILST][0:20] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
		cmds[CRDID7][IRDY][0:20] = 0;
		//                         | WriteEn|        | Write CR0 = 8FEF to give LAT=3    |        | WriteEn (again!)
		//   WRITE Latency 3       | CMD    | CS     | CMD    | A0     | A1     | CR     | CS     | CMD    
		//                         | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      
		cmds[CWRLAT][ICLK][0:07] = {16'h0110,16'h0000,16'h0110,16'h0110,16'h0110,16'h0110,16'h0000,16'h0110};
		cmds[CWRLAT][ICS ][0:07] = {16'h1111,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000,16'h1111};
		cmds[CWRLAT][IDOE][0:07] = {16'h1111,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000,16'h1111};
		cmds[CWRLAT][IDQH][0:07] = {16'h0000,16'h0000,16'h7777,16'h0000,16'h0000,16'h88EE,16'h0000,16'h0000};
		cmds[CWRLAT][IDQL][0:07] = {16'h6666,16'h0000,16'h1111,16'h0000,16'h0044,16'hFFFF,16'h0000,16'h6666};
		cmds[CWRLAT][ILE ][0:07] = 0;
		cmds[CWRLAT][ISOE][0:07] = 0;
		cmds[CWRLAT][ILST][0:07] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
		cmds[CWRLAT][IRDY][0:07] = 0;
		//                         | Read Mem, BL=8
		//   Read Burst 8          | CMD    | A0     | A1     | L1     | L2     | L3     | L1     | L2     | L3     | Extra  | R0     | R1     | R2     | R3     | del    |
		//                         | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      | 8      | 9      | 10     | 11     | 12     | 13     | 14     |
		cmds[CRDMEM][ICLK][0:14] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0000};
		cmds[CRDMEM][ICS ][0:14] = {16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000};
		cmds[CRDMEM][IDOE][0:14] = {16'h1111,16'h1111,16'h1111,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
		cmds[CRDMEM][IDQH][0:14] = {16'hEEEE, arh0   , arh1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
		cmds[CRDMEM][IDQL][0:14] = {16'hEEEE, arl0   , arl1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000};
		cmds[CRDMEM][ILE ][0:14] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0010,16'h2010,16'h2010,16'h2010,16'h2000};
		cmds[CRDMEM][ISOE][0:14] = 0;                                                                      
		cmds[CRDMEM][ILST][0:14] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
		cmds[CRDMEM][IRDY][0:14] = 0;
		//                         | Write Mem, BL=16
		//   WRITE Burst           | CMD    | A0     | A1     | L1     | L2     | L3     | L1     | L2     | L3     | Extra  | W0     | W1     | W2     | W3     | W4     | W5     | W6     | W7     |
		//                         | 0      | 1      | 2      | 3      | 4      | 5      | 6      | 7      | 8      | 9      | 10     | 11     | 12     | 13     | 14     | 15     | 16     | 17     |
		cmds[CWRMEM][ICLK][0:17] = {16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110,16'h0110};
		cmds[CWRMEM][ICS ][0:17] = {16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111};
		cmds[CWRMEM][IDOE][0:17] = {16'h1111,16'h1111,16'h1111,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111};
		cmds[CWRMEM][IDQH][0:17] = {16'hDDDD, awh0   , awh1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,  dh    ,  dh    ,  dh    ,  dh    ,  dh    ,  dh    ,  dh    ,  dh    };
		cmds[CWRMEM][IDQL][0:17] = {16'hEEEE, awl0   , awl1   ,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,  dl    ,  dl    ,  dl    ,  dl    ,  dl    ,  dl    ,  dl    ,  dl    };
		cmds[CWRMEM][ILE ][0:17] = 0;                                                                      
		cmds[CWRMEM][ISOE][0:17] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111};
		cmds[CWRMEM][ILST][0:17] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111};
		cmds[CWRMEM][IRDY][0:17] = {16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h0000,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h1111,16'h0000,16'h0000};
	end
	
	
	// Add command gating and pack for Reduction 
	always_comb begin : _cmd_gate
		for( int cmd_idx = 0; cmd_idx <= 4; cmd_idx++ )
			for( int sig_idx = 0; sig_idx <= 8; sig_idx++ )
				for( int st_idx = 0; st_idx <= 24; st_idx++ )
					for( int ph_idx = 0; ph_idx <= 3; ph_idx++ )
						for( int nib_idx = 0; nib_idx <= 3; nib_idx++ ) begin
							gated_cmds[sig_idx][nib_idx][ph_idx][cmd_idx][st_idx] = cmd_sreg[cmd_idx][st_idx] & cmds[cmd_idx][sig_idx][st_idx][ph_idx][nib_idx]; // AND gated
						end
	end
	
	// Registered Reduction ORs
	always @(posedge clk) begin : _cmd_reduction_regs
		for( int sig_idx = 0; sig_idx <= 8; sig_idx++ )
			for( int ph_idx = 0; ph_idx <= 3; ph_idx++ )
				for( int nib_idx = 0; nib_idx <= 3; nib_idx++ ) begin
							cmds_reg[sig_idx][nib_idx][ph_idx] <= |gated_cmds[sig_idx][nib_idx][ph_idx]; // Reduction OR (yes!!!)
				end
	end

	// Determine clk4 phase  0.1.2.3 in order
	logic [3:0] ph; 
	phase4 _phase4 ( .clk(clk), .clk4(clk4), .phase(ph) );

	// Phase Muxing to 4x rate
	always_comb begin : _cmd_phase_mux
		for( int sig_idx = 0; sig_idx <= 8; sig_idx++ )
			for( int nib_idx = 0; nib_idx <= 3; nib_idx++ ) begin
				cmds_x4[sig_idx][nib_idx] = 		ph[0] & cmds_reg[sig_idx][nib_idx][0] |
													ph[1] & cmds_reg[sig_idx][nib_idx][1] |
													ph[2] & cmds_reg[sig_idx][nib_idx][2] |
													ph[3] & cmds_reg[sig_idx][nib_idx][3] ;
			end
	end
		
	// Connect up Last 
	logic lastq; // registered flag for last.
	assign lastq = cmds_reg[ILST][0][0];
	
	// Wire up phase reduction

	// Connect UP spi outputs
	always @(posedge clk4) begin : _spi_oregs
		if( reset ) begin
			spi_data_out[7:0] <= 0;
			spi_data_oe			<= 0;
			spi_le_out[1:0]	<= 0;
			spi_clk				<= 0;
			spi_cs				<= 0;
			spi_rwds_out		<= 0;
			spi_rwds_oe			<= 0;
		end else begin
			spi_clk				<= cmds_x4[ICLK][0];
			spi_cs				<= cmds_x4[ICS ][0];	
			spi_rwds_out		<= cmds_x4[ISOE][1];
			spi_rwds_oe			<= cmds_x4[ISOE][0];
			spi_le_out			<= cmds_x4[ILE ][1:0];
			spi_data_oe			<= cmds_x4[IDOE][0];
			spi_data_out[7:4] <= cmds_x4[IDQH][3:0];
			spi_data_out[3:0] <= cmds_x4[IDQL][3:0];		
		end
	end
	
	


	
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
	logic [12:0] delay;
	
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
				STATE_READY        :	next_state = 	( awvalid ) ? 	STATE_CMD_WRMEM :
																( arvalid ) ? 	STATE_CMD_RDMEM :
																					STATE_READY     ;
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
			delay <= delay - 13'd1;
		end
	end

	// PSRAM_READY after STATE_READY
	always @(posedge clk) begin
		if( reset ) begin
			psram_ready <= 0;
		end else begin
			psram_ready <= ( state == STATE_READY ) ? 1'b1 : psram_ready;
		end
	end

	/////////////////////
	// AXI4 Ports
	/////////////////////
	
		// Write Data
		assign wready = cmds_reg[IRDY][0][0];	
		
		// register addressed
	
		always @(posedge clk) begin
			awaddr_reg <= ( awvalid && awready ) ? awaddr : awaddr_reg;
			araddr_reg <= ( arvalid && arready ) ? araddr : araddr_reg;
		end

		assign awready = ( state == STATE_READY && next_state == STATE_CMD_WRMEM ) ? 1'b1 : 1'b0;
		assign arready = ( state == STATE_READY && next_state == STATE_CMD_RDMEM ) ? 1'b1 : 1'b0;
		
		// Write Response
		assign bvalid = ( state == STATE_CMD_WRMEM_WAIT && lastq ) ? 1'b1 : 1'b0;
		assign bresp = 2'b00;

		// Read Data (connected below in read data latch)
		
////////////////////
/// Command shift Regs
//////////////////////

	// Connect up shift registers
	always_comb begin : _cmd_sregisters
		// default zero
		cmd_sreg_d = 0;
		// Connect inputs, inserts pulses
		cmd_sreg_d[CRESET][0] = ( state == STATE_CMD_RESET ) ? 1'b1 : 1'b0;
		cmd_sreg_d[CRDID7][0] = ( state == STATE_CMD_RDID7 ) ? 1'b1 : 1'b0;
		cmd_sreg_d[CWRLAT][0] = ( state == STATE_CMD_WRLAT ) ? 1'b1 : 1'b0;
		cmd_sreg_d[CRDMEM][0] = ( state == STATE_CMD_RDMEM ) ? 1'b1 : 1'b0;
		cmd_sreg_d[CWRMEM][0] = ( state == STATE_CMD_WRMEM ) ? 1'b1 : 1'b0;
		// connect up chains
		for( int idx = 1; idx < 3; idx++ ) cmd_sreg_d[CRESET][idx] = cmd_sreg[CRESET][idx-1];
		for( int idx = 1; idx <21; idx++ ) cmd_sreg_d[CRDID7][idx] = cmd_sreg[CRDID7][idx-1];
		for( int idx = 1; idx < 8; idx++ ) cmd_sreg_d[CWRLAT][idx] = cmd_sreg[CWRLAT][idx-1];
		for( int idx = 1; idx <15; idx++ ) cmd_sreg_d[CRDMEM][idx] = cmd_sreg[CRDMEM][idx-1];
		for( int idx = 1; idx <18; idx++ ) cmd_sreg_d[CWRMEM][idx] = cmd_sreg[CWRMEM][idx-1];
	end
	
	always @(posedge clk) begin
		if( reset ) begin
			cmd_sreg <= 0;
		end else begin
			cmd_sreg <= cmd_sreg_d;	
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
		
		// AXI4 Read Data Port
		
		always @(posedge clk) begin
			rdata  <= ( delay_le1[3] ) ? data_le1_reg : rdata;
			rvalid <=   delay_le1[3];
		end

	
endmodule

module phase4( 
	input  logic clk,
	input  logic clk4,
	output logic [3:0] phase
	);
	
	logic toggle = 0;
	logic toggle_del;
	
	always @(posedge clk) toggle <= !toggle;
	
	always @(posedge clk4 ) begin
		toggle_del <= toggle;
		phase[1] <= toggle ^ toggle_del;
		phase[2] <= phase[1];
		phase[3] <= phase[2];
		phase[0] <= phase[3];
	end
endmodule
	
	