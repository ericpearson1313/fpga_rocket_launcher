// Controller PSRAM with SPI8 interface.
// Starts us and allows access to a 32 Mbyte sram. (16M x 16)

module psram_ctrl(
		// System
		
		input clk,
		input clkx4,
		input reset,

		// Psram spi8 interface
		// Run on Clk4x
		output [7:0] 	spi_data_out,
		output   		spi_data_oe,
		input  [7:0] 	spi_data_in,
		output			spi_clk,
		output			spi_cs,
		output			spi_rwds_out,
		output			spi_rsds_oe,
		input				spi_rwds_in,
		
		// Status
		output			psram_ready,	// Indicates control is ready to accept requests
		output [31:0]	dev_id,			// Should be should be 32'h0E96_0001
		
		// AXI4 R/W port
		// Write Data
		input	[15:0]	wdata,
		input				wvalid,	// assumed 1, non blocking, data is available
		output			wready,
		// Write Addr
		input	[24:0]	awaddr,
		input	[7:0]		awlen,	// assumed 8
		input				awvalid, 
		output			awready,
		// Write Response
		input				bready,	// Assume 1, non blocking
		output			bvalid,
		output	[1:0]	bresp,
		// Read Addr
		input	[24:0]	araddr,
		input	[7:0] 	arlen,	// assumed 4
		input				arvalid,	
		output			arready,
		// Read Data
		output [15:0]	rdata,
		output 			rvalid,
		input				rready // Assumed 1, non blocking
		);
	
	
	// State machine
	 typedef enum {
         STATE_IDLE,		// Reset
         STATE_STARTUP,	// wait 150us
			STATE_CMD_RESET_00, // Reset Enable + Reset 25 cyc (includes delay)
			STATE_CMD_RESET_01,
			STATE_CMD_RESET_02,
			STATE_CMD_RESET_03,
			STATE_CMD_RESET_04,
			STATE_CMD_RESET_05,
			STATE_CMD_RESET_06,
			STATE_CMD_RESET_07,
			STATE_CMD_RESET_08,
			STATE_CMD_RESET_09,
			STATE_CMD_RESET_10,
			STATE_CMD_RESET_11,
			STATE_CMD_RESET_12,
			STATE_CMD_RESET_13,
			STATE_CMD_RESET_14,
			STATE_CMD_RESET_15,
			STATE_CMD_RESET_16,
			STATE_CMD_RESET_17,
			STATE_CMD_RESET_18,
			STATE_CMD_RESET_19,
			STATE_CMD_RESET_20,
			STATE_CMD_RESET_21,
			STATE_CMD_RESET_22,
			STATE_CMD_RESET_23,
			STATE_CMD_RESET_24,
			STATE_CMD_RD_ID_00,	// Read ID regs (20 cyc in lat=7)
			STATE_CMD_RD_ID_01,
			STATE_CMD_RD_ID_02,	
			STATE_CMD_RD_ID_03,	
			STATE_CMD_RD_ID_04,	
			STATE_CMD_RD_ID_05,	
			STATE_CMD_RD_ID_06,	
			STATE_CMD_RD_ID_07,	
			STATE_CMD_RD_ID_08,	
			STATE_CMD_RD_ID_09,	
			STATE_CMD_RD_ID_10,	
			STATE_CMD_RD_ID_11,	
			STATE_CMD_RD_ID_12,	
			STATE_CMD_RD_ID_13,	
			STATE_CMD_RD_ID_14,	
			STATE_CMD_RD_ID_15,	
			STATE_CMD_RD_ID_16,	
			STATE_CMD_RD_ID_17,	
			STATE_CMD_RD_ID_18,	
			STATE_CMD_RD_ID_19,
		   STATE_CMD_WRLAT_00, // Write enable + write to CR0
		   STATE_CMD_WRLAT_01,
		   STATE_CMD_WRLAT_02,
		   STATE_CMD_WRLAT_03,
		   STATE_CMD_WRLAT_04,
		   STATE_CMD_WRLAT_05,
		   STATE_CMD_WRLAT_06,
			STATE_CMD_RDMEM_00,	// read 4x16b burst, LAT=3
			STATE_CMD_RDMEM_01,				
			STATE_CMD_RDMEM_02,				
			STATE_CMD_RDMEM_03,				
			STATE_CMD_RDMEM_04,				
			STATE_CMD_RDMEM_05,				
			STATE_CMD_RDMEM_06,				
			STATE_CMD_RDMEM_07,				
			STATE_CMD_RDMEM_08,				
			STATE_CMD_RDMEM_09,				
			STATE_CMD_RDMEM_10,				
			STATE_CMD_RDMEM_11,				
			STATE_CMD_RDMEM_12,				
			STATE_CMD_RDMEM_13,		
			STATE_CMD_WRMEM_00, // write 8x16b burst, LAT=3
			STATE_CMD_WRMEM_01,
			STATE_CMD_WRMEM_02,
			STATE_CMD_WRMEM_03,
			STATE_CMD_WRMEM_04,
			STATE_CMD_WRMEM_05,
			STATE_CMD_WRMEM_06,
			STATE_CMD_WRMEM_07,
			STATE_CMD_WRMEM_08,
			STATE_CMD_WRMEM_09,
			STATE_CMD_WRMEM_10,
			STATE_CMD_WRMEM_11,
			STATE_CMD_WRMEM_12,
			STATE_CMD_WRMEM_13,
			STATE_CMD_WRMEM_14,
			STATE_CMD_WRMEM_15,
			STATE_CMD_WRMEM_16,
			STATE_CMD_WRMEM_17,
			STATE_READY 			// Ready to recieve command
   } State;
   State state;		
   State next_state;
	
	always @(posedge clk) begin
      state <= next_state;
   end
   
    //                                    | Reset_En| Soft Reset and then delay
	//                                     | CMD| CS | CMD|  <------ 400 nSec Reset Delay = 20 cycles ------------------------------------------------------> |
	//                                     | 0  | 1  | 2  | 3  | 4  | 5  | 6  | 7  | 8  | 9  | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
	logic [99:0]      cmd_reset_clk = {100'b0110_0000_0110_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:1]      cmd_reset_cs  = {100'b1111_0000_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_reset_doe = {100'b1111_0000_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0][3:0] cmd_reset_dqh = {400'h6666_0000_9999_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0][3:0] cmd_reset_dql = {400'h6666_0000_9999_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_reset_leh = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_reset_lel = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_reset_soe = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0] 	   cmd_reset_rws = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0] 	   cmd_reset_last= {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_1111_0000_0000};
	
    //                                     | Read ID Lat=7
	//                                     | CMD| A0 | A1 | L1 | L2 | L3 | L4 | L5 | L6 | L7 | L1 | L2 | L3 | L4 | L5 | L6 | L7 | ID0| ID1| del
	//                                     | 0  | 1  | 2  | 3  | 4  | 5  | 6  | 7  | 8  | 9  | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
	logic [99:0]      cmd_rd_id_clk = {100'b0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_rd_id_csn = {100'b1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_rd_id_doe = {100'b1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0][3:0] cmd_rd_id_dqh = {400'h9999_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0][3:0] cmd_rd_id_dql = {400'hFFFF_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_rd_id_leh = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0010_0010_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_rd_id_lel = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_1000_1000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_rd_id_soe = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0] 	   cmd_rd_id_rws = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0] 	   cmd_rd_id_last= {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_1111_0000_0000_0000_0000_0000};
		
	
	//                                     | Write En| Write CR0 = 4FEF to give LAT=3
	//                                     | CMD| CS | CMD| A0 | A1 | CR |
	//                                     | 0  | 1  | 2  | 3  | 4  | 5  | 6  | 7  | 8  | 9  | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
	logic [99:0]      cmd_wrlat_clk = {100'b0110_0110_0110_0110_0110_0110_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_wrlat_csn = {100'b1111_0000_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_wrlat_doe = {100'b1111_0000_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0][3:0] cmd_wrlat_dqh;
	assign cmd_wrlat_dqh = {400'h0000_0000_7777_0000_0000_88EE_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0][3:0] cmd_wrlat_dql = {400'h6666_0000_1111_0000_0000_FFFF_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_wrlat_leh = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_wrlat_lel = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0]      cmd_wrlat_soe = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0] 	   cmd_wrlat_rws = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};
	logic [99:0] 	   cmd_wrlat_last= {100'b0000_0000_0000_0000_0000_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000};

	logic [31:0] a;
	logic [31:0] adrh = { a[31:28], a[31:28], a[23:20], a[23:20], a[15:12], a[15:12], a[ 7: 4], a[ 7: 4] };
	logic [31:0] adrl = { a[27:24], a[27:24], a[19:16], a[19:16], a[11: 8], a[11: 8], a[ 3: 0], a[ 3: 0] };
	
	//                                     | Read Mem, BL=8
	//                                     | CMD| A0 | A1 | L1 | L2 | L3 | L1 | L2 | L3 | R0 | R1 | R2 | R3 | del
	//                                     | 0  | 1  | 2  | 3  | 4  | 5  | 6  | 7  | 8  | 9  | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
	logic [99:0]      cmd_rdmem_clk = {100'b0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_rdmem_cs  = {100'b1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_rdmem_doe = {100'b1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0][3:0] cmd_rdmem_dqh = { 16'hEEEE,adrh,352'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0][3:0] cmd_rdmem_dql = { 16'hEEEE,adrl,352'h0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_rdmem_leh = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0010_0010_0010_0010_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_rdmem_lel = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_1000_1000_1000_1000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_rdmem_soe = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0] 	   cmd_rdmem_rws = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0] 	   cmd_rdmem_last= {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_1111_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	
	
	logic [15:0] d;
	logic [15:0] dh;
	logic [15:0] dl;
	assign dh[15:0] = { {2{d[15:12]}}, {2{d[7:4]}} };
	assign dl[15:0] = { {2{d[11: 8]}}, {2{d[3:0]}} };
	
	//                                     | Write Mem, BL=16
	//                                     | CMD| A0 | A1 | L1 | L2 | L3 | L1 | L2 | L3 | W0 | W1 | W2 | W3 | W4 | W5 | W6 | W7 |
	//                                     | 0  | 1  | 2  | 3  | 4  | 5  | 6  | 7  | 8  | 9  | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 | 22 | 23 | 24 |
	logic [99:0]      cmd_wrmem_clk = {100'b0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0110_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_wrmem_cs  = {100'b1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_wrmem_doe = {100'b1111_1111_1111_0000_0000_0000_0000_0000_0000_1111_1111_1111_1111_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0][3:0] cmd_wrmem_dqh = { 16'hEEEE,adrh, 96'h0000_0000_0000_0000_0000_0000,dh,  dh,  dh,  dh,  dh, dh, dh, dh,128'h0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0][3:0] cmd_wrmem_dql = { 16'hEEEE,adrl, 96'h0000_0000_0000_0000_0000_0000,dl,  dl,  dl,  dl,  dl, dl, dl, dl,128'h0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_wrmem_leh = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_wrmem_lel = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0]      cmd_wrmem_soe = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_1111_1111_1111_1111_1111_1111_1111_1111_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0] 	   cmd_wrmem_rws = {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000 };
	logic [99:0] 	   cmd_wrmem_last= {100'b0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_0000_1111_0000_0000_0000_0000_0000_0000_0000_0000 };

   always_comb begin
      if(reset) begin
         next_state = STATE_IDLE;
      end else begin
         case(state)
				STATE_IDLE: begin
						next_state = STATE_STARTUP;
					end
				// wait for 150 Usec after reset/power up.
				STATE_STARTUP : 		next_state = ( delay == 0 ) ? STATE_CMD_RESET_00 : STATE_STARTUP;
				// Reset Device and wait 400ns
				STATE_CMD_RESET_00 : next_state = STATE_CMD_RESET_01;
				STATE_CMD_RESET_01 : next_state = STATE_CMD_RESET_02;
				STATE_CMD_RESET_02 : next_state = STATE_CMD_RESET_03;
				STATE_CMD_RESET_03 : next_state = STATE_CMD_RESET_04;
				STATE_CMD_RESET_04 : next_state = STATE_CMD_RESET_05;
				STATE_CMD_RESET_05 : next_state = STATE_CMD_RESET_06;
				STATE_CMD_RESET_06 : next_state = STATE_CMD_RESET_07;
				STATE_CMD_RESET_07 : next_state = STATE_CMD_RESET_08;
				STATE_CMD_RESET_08 : next_state = STATE_CMD_RESET_09;
				STATE_CMD_RESET_09 : next_state = STATE_CMD_RESET_10;
				STATE_CMD_RESET_10 : next_state = STATE_CMD_RESET_11;
				STATE_CMD_RESET_11 : next_state = STATE_CMD_RESET_12;
				STATE_CMD_RESET_12 : next_state = STATE_CMD_RESET_13;
				STATE_CMD_RESET_13 : next_state = STATE_CMD_RESET_14;
				STATE_CMD_RESET_14 : next_state = STATE_CMD_RESET_15;
				STATE_CMD_RESET_15 : next_state = STATE_CMD_RESET_16;
				STATE_CMD_RESET_16 : next_state = STATE_CMD_RESET_17;
				STATE_CMD_RESET_17 : next_state = STATE_CMD_RESET_18;
				STATE_CMD_RESET_18 : next_state = STATE_CMD_RESET_19;
				STATE_CMD_RESET_19 : next_state = STATE_CMD_RESET_20;
				STATE_CMD_RESET_20 : next_state = STATE_CMD_RESET_21;
				STATE_CMD_RESET_21 : next_state = STATE_CMD_RESET_22;
				STATE_CMD_RESET_22 : next_state = STATE_CMD_RESET_23;
				STATE_CMD_RESET_23 : next_state = STATE_CMD_RESET_24;
				STATE_CMD_RESET_24 : next_state = STATE_CMD_RD_ID_00;
				// Read the ID regs (lat 7)
				STATE_CMD_RD_ID_00 : next_state = STATE_CMD_RD_ID_01;	
				STATE_CMD_RD_ID_01 : next_state = STATE_CMD_RD_ID_02;
				STATE_CMD_RD_ID_02 : next_state = STATE_CMD_RD_ID_03;	
				STATE_CMD_RD_ID_03 : next_state = STATE_CMD_RD_ID_04;	
				STATE_CMD_RD_ID_04 : next_state = STATE_CMD_RD_ID_05;	
				STATE_CMD_RD_ID_05 : next_state = STATE_CMD_RD_ID_06;	
				STATE_CMD_RD_ID_06 : next_state = STATE_CMD_RD_ID_07;	
				STATE_CMD_RD_ID_07 : next_state = STATE_CMD_RD_ID_08;	
				STATE_CMD_RD_ID_08 : next_state = STATE_CMD_RD_ID_09;	
				STATE_CMD_RD_ID_09 : next_state = STATE_CMD_RD_ID_10;	
				STATE_CMD_RD_ID_10 : next_state = STATE_CMD_RD_ID_11;	
				STATE_CMD_RD_ID_11 : next_state = STATE_CMD_RD_ID_12;	
				STATE_CMD_RD_ID_12 : next_state = STATE_CMD_RD_ID_13;	
				STATE_CMD_RD_ID_13 : next_state = STATE_CMD_RD_ID_14;	
				STATE_CMD_RD_ID_14 : next_state = STATE_CMD_RD_ID_15;	
				STATE_CMD_RD_ID_15 : next_state = STATE_CMD_RD_ID_16;	
				STATE_CMD_RD_ID_16 : next_state = STATE_CMD_RD_ID_17;	
				STATE_CMD_RD_ID_17 : next_state = STATE_CMD_RD_ID_18;	
				STATE_CMD_RD_ID_18 : next_state = STATE_CMD_RD_ID_19;	
				STATE_CMD_RD_ID_19 : next_state = STATE_CMD_WRLAT_00;
				// Write Enable and write CR0 (for lat=3)
				STATE_CMD_WRLAT_00 : next_state = STATE_CMD_WRLAT_01;
            STATE_CMD_WRLAT_01 : next_state = STATE_CMD_WRLAT_02;
            STATE_CMD_WRLAT_02 : next_state = STATE_CMD_WRLAT_03;
            STATE_CMD_WRLAT_03 : next_state = STATE_CMD_WRLAT_04;
            STATE_CMD_WRLAT_04 : next_state = STATE_CMD_WRLAT_05;
            STATE_CMD_WRLAT_05 : next_state = STATE_CMD_WRLAT_06;
				STATE_CMD_WRLAT_06 : next_state = STATE_READY;
				// Read a burst of 8bytes (4x16b) from memory
				STATE_CMD_RDMEM_00 : next_state = STATE_CMD_RDMEM_01;
				STATE_CMD_RDMEM_01 : next_state = STATE_CMD_RDMEM_02;				
				STATE_CMD_RDMEM_02 : next_state = STATE_CMD_RDMEM_03;				
				STATE_CMD_RDMEM_03 : next_state = STATE_CMD_RDMEM_04;				
				STATE_CMD_RDMEM_04 : next_state = STATE_CMD_RDMEM_05;				
				STATE_CMD_RDMEM_05 : next_state = STATE_CMD_RDMEM_06;				
				STATE_CMD_RDMEM_06 : next_state = STATE_CMD_RDMEM_07;				
				STATE_CMD_RDMEM_07 : next_state = STATE_CMD_RDMEM_08;				
				STATE_CMD_RDMEM_08 : next_state = STATE_CMD_RDMEM_09;				
				STATE_CMD_RDMEM_09 : next_state = STATE_CMD_RDMEM_10;				
				STATE_CMD_RDMEM_10 : next_state = STATE_CMD_RDMEM_11;				
				STATE_CMD_RDMEM_11 : next_state = STATE_CMD_RDMEM_12;				
				STATE_CMD_RDMEM_12 : next_state = STATE_CMD_RDMEM_13;				
				STATE_CMD_RDMEM_13 : next_state = STATE_READY;						
				// Write a curst of 16 bytes (8x16b)
				STATE_CMD_WRMEM_00 : next_state = STATE_CMD_WRMEM_01;
				STATE_CMD_WRMEM_01 : next_state = STATE_CMD_WRMEM_02;
				STATE_CMD_WRMEM_02 : next_state = STATE_CMD_WRMEM_03;
				STATE_CMD_WRMEM_03 : next_state = STATE_CMD_WRMEM_04;
				STATE_CMD_WRMEM_04 : next_state = STATE_CMD_WRMEM_05;
				STATE_CMD_WRMEM_05 : next_state = STATE_CMD_WRMEM_06;
				STATE_CMD_WRMEM_06 : next_state = STATE_CMD_WRMEM_07;
				STATE_CMD_WRMEM_07 : next_state = STATE_CMD_WRMEM_08;
				STATE_CMD_WRMEM_08 : next_state = STATE_CMD_WRMEM_09;
				STATE_CMD_WRMEM_09 : next_state = STATE_CMD_WRMEM_10;
				STATE_CMD_WRMEM_10 : next_state = STATE_CMD_WRMEM_11;
				STATE_CMD_WRMEM_11 : next_state = STATE_CMD_WRMEM_12;
				STATE_CMD_WRMEM_12 : next_state = STATE_CMD_WRMEM_13;
				STATE_CMD_WRMEM_13 : next_state = STATE_CMD_WRMEM_14;
				STATE_CMD_WRMEM_14 : next_state = STATE_CMD_WRMEM_15;
				STATE_CMD_WRMEM_15 : next_state = STATE_CMD_WRMEM_16;
				STATE_CMD_WRMEM_16 : next_state = STATE_CMD_WRMEM_17;
				STATE_CMD_WRMEM_17 : next_state = STATE_READY;				
				// Ready for command, recieve and dispatch
				STATE_READY        :	next_state = 	( arvalid ) ? 	STATE_CMD_RDMEM_00 :
																( awvalid ) ? 	STATE_CMD_WRMEM_00 :
																					STATE_READY;
				default				 :	next_state = STATE_IDLE;
         endcase
      end
   end
	
	logic [12:0] delay;
	always @(posedge clk) begin
		if( reset ) begin
			delay <= 13'd7200; // 150usec with 48 Mhz clk
		end else if ( delay == 0 ) begin
			delay <= 0;
		end else begin
			delay <= delay - 1;
		end
   end
	
endmodule
	