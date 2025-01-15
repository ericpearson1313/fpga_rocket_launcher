`timescale 1ns / 1ps
module blaster_chip

#(
	// Parameter Declarations
	parameter UNIQ_ID = 32'h0000_0000
)

(
	// Input Buttons
	input  logic arm_button,
	input  logic fire_button,

	// Output LED/SPK
	output logic arm_led_n,
	output logic cont_led_n,
	output logic speaker,
	output logic speaker_n,
	
	// Bank 1A: Analog Inputs / IO
	output [8:1] anain,
	
	// Bank 7, future serial port
	inout [6:0] digio,
	
	// Bank 1B Rs232
	input 		rx232,
	output 		tx232,
	
	// High Voltage 
	output logic lt3420_charge,
	input  logic lt3420_done,
	output logic pwm,	
	output logic dump,
	input  logic cont_n,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	output logic		  ad_sclk,
	input  logic  [1:0] ad_sdata_a,
	input  logic  [1:0] ad_sdata_b,
	input  logic        CIdiag,
	input  logic        CVdiag,
	input  logic        LIdiag,
	input  logic 		  LVdiag,
	
	// External Current Control Input
	input	 logic  [2:0] iset, // Current target in unit amps  
	
	// SPI8 Bus
	inout  wire [7:0]  spi8_data_pad,   //   pad_io.export
	inout  wire spi_clk0,
	inout  wire spi_ncs,
	inout  wire spi_ds,
	inout  wire spi_nrst,
	
	// HDMI Output 1 (Tru LVDS)
	output logic		hdmi_d0,
	output logic		hdmi_d1,
	output logic		hdmi_d2,
	output logic      hdmi_ck,

	// HDMI Output 2 (Tru LVDS)
	output logic		hdmi2_d0,
	output logic		hdmi2_d1,
	output logic		hdmi2_d2,
	output logic      hdmi2_ck,
	
	// Input clock, reset
	output logic clk_out, // Differential output
	input logic clk_in,	// Reference 48Mhz or other
	input logic reset_n
);

	logic [4:0] key; // keypad, bit 4 indicates pressed



// PLL (only 1 PLL in E144 package!)

logic clk;	// global 48Mhz clock
logic clk4; // global 192MhZ spi8 clk
logic hdmi_clk; 	// Pixel clk, apparentlyi can support 720p
logic hdmi_clk5;  // 5x pixel clk clock for data xmit, 10b*3=30/3lanes=10ddr=5 

spi8_pll _spll(
	.inclk0 (clk_in),		// External clock input
	.c0     (clk_out), 	// External clock output differential
	.c1	  (clk),			// Global Clock ADC rate 48 Mhz
	.c2	  (clk4),		// Global Clock SPI8 rate 192 Mhz
	.c3	  (hdmi_clk),	// HDMI pixel clk
	.c4	  (hdmi_clk5)  // HDMI ddr clock 5x
	);
	
assign ad_sclk  = !clk;

// delayed from fpga config and external reset d-assert

logic [3:0] reset_shift = 0; // initial value upon config
always @(posedge clk) begin
		if( !reset_n ) begin
			reset_shift <= 4'h0;
		end else begin
			if( reset_shift != 4'HF ) begin
				reset_shift[3:0] <= reset_shift[3:0] + 4'h1;
			end else begin
				reset_shift[3:0] <= reset_shift[3:0];
			end
		end
end

logic reset;
assign reset = (reset_shift[3:0] != 4'hF) ? 1'b1 : 1'b0; // reset de-asserted after all bit shifted in 


// Continuity active low
logic cont;
assign cont = !cont_n;

/////////////////////////////////////////////////////////

// Dig I/O divided clocks
logic [9:0] div_in, div_c0, div_c1, div_c2, div_c3, div_c4, div_c5;

always @(posedge clk_in		) div_in <= div_in + 1;
always @(posedge clk_out   ) div_c0 <= div_c0 + 1;
always @(posedge clk   		) div_c1 <= div_c1 + 1;
always @(posedge clk4   	) div_c2 <= div_c2 + 1;
always @(posedge hdmi_clk  ) div_c3 <= div_c3 + 1;
always @(posedge hdmi_clk5 ) div_c4 <= div_c4 + 1;
always @(posedge clk 		) div_c5 <= div_c5 + 1;

//assign digio[6:0] = { 1'b0,
//							 div_c5[9],
//						    div_c4[9],
//						    div_c3[9],
//						    div_c2[9],
//						    div_c1[9],
//						    div_c0[9],
//						    div_in[9] };

// Rs232 loopback
assign tx232 = rx232;
// LEDs active low
logic arm_led;
logic cont_led;
assign arm_led_n = !arm_led;
assign cont_led_n = !cont_led;

// AIN
assign anain[3:1] = iset[2:0]; // active low switch inputs
assign anain[4] = !reset;
logic [24:0] count;
always @(posedge clk) begin
	count <= count + 1;
end
assign anain[8:5] = count[24:21];
assign anain[8]=count[24];

//assign speaker = count[14]  & (!iset[0] || key == 5'h11);
assign dump = !iset[1]  | key == 5'h1B;
assign cont_led = !(!iset[1] | cont); 
assign arm_led = fire_button | lt3420_done ;
assign lt3420_charge = !iset[2] | key == 5'h1A;

				 


////////////////////////////////
//////////////////////////////



// Speaker is differential out gives 6Vp-p
logic [15:0] tone_cnt;
logic spk_en, spk_toggle;

always @(posedge clk) begin
	if( tone_cnt == 0 ) begin
		spk_toggle <= !spk_toggle;
		{spk_en, tone_cnt}<= ( key == 5'h11 ) ? { 1'b1, 16'h2CCA } :
								   ( key == 5'h12 ) ? { 1'b1, 16'h27E7 } :
								   ( key == 5'h13 ) ? { 1'b1, 16'h238D } :
								   ( key == 5'h14 ) ? { 1'b1, 16'h218E } :
								   ( key == 5'h15 ) ? { 1'b1, 16'h1DE5 } :
								   ( key == 5'h16 ) ? { 1'b1, 16'h1AA2 } :
								   ( key == 5'h17 ) ? { 1'b1, 16'h17BA } :
								   ( key == 5'h18 ) ? { 1'b1, 16'h1665 } : 0;
	end else begin
		tone_cnt <= tone_cnt - 1;
		spk_en <= spk_en;
		spk_toggle <= spk_toggle;
	end
end

assign speaker = spk_toggle & spk_en ; 
assign speaker_n = !speaker;



logic [11:0] ad_a0, ad_a1, ad_b0, ad_b1;
logic ad_strobe;

////////////////////////////////////////////
// PWM Current limited pulse generator
////////////////////////////////////////////

	logic pwm_pulse;
logic [15:0] pulse_time;
logic [3:0] pulse_count;


always @(posedge clk) begin
	if( reset ) begin
		pwm_pulse <= 0;
		pulse_time <= 0;
		pulse_count <= 0;
	end else begin
		if( pwm_pulse ) begin // turn off pulse if time or current level exceeded
			if( pulse_time < 48 ) begin // min pulse width
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count	
			end else if(( pulse_time >= (48  * 16))    || // usec @ 48 Mhz 
			   ( !ad_a0[11] && ((ad_a0 ^ 12'h7FF) > (205 * 2 + 20)))) begin //  >2 amp * 205 DN/A measured + 10%
				pwm_pulse <= 0;
				pulse_time <= 0;
				pulse_count <= pulse_count - 1;
			end else begin
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count
			end
		end else if( !pwm_pulse && pulse_count > 0 ) begin // wait for ad_a0 to fall
			if( pulse_time < 48 ) begin // min pulse width
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count					
			end else if ( ( ad_a0[11] || ((ad_a0 ^ 12'h7FF) < (205 * 2 - 20))) ) begin //  <2 amp * 205 DN/A measured - 10%
				pwm_pulse <= 1;
				pulse_time <= 1;
				pulse_count <= pulse_count;
			end else begin
				pwm_pulse <= 0;
				pulse_time <= pulse_time + 1; 
				pulse_count <= pulse_count;
			end			
		end else if( (fire_button || key == 5'h10) && count[15:0] == 0 ) begin // (re)Triggered by fire key at 64k/48Mhz=1.3ms period
			pwm_pulse <= 1; // Set pwm output
			pulse_time <= 1; // start max width counter
			pulse_count <= 3; // two pulses
		end else begin // await trigger
			pwm_pulse <= 0;
			pulse_time <= 0;		
			pulse_count <= 0;
		end
	end
end



blaster _blaster (
	// Input Buttons
	.arm_button( arm_button ), // arm is the power button, does this make sense
	.fire_button( fire_button ), // active high

	// Output LED/SPK
	.arm_led( /*arm_led*/ ),
	.cont_led( /*cont_led*/ ),
	.speaker( /*speaker*/ ),
	
	// Charger
	.lt3420_done( lt3420_done ),
	.lt3420_charge( /*lt3420_charge*/ ),

	// Voltage Controls
	.pwm( /*pwm*/ ),
	.dump( /*dump*/ ),

	// Continuity feedback
	.cont( cont ),
	
	// Current setting
	.iset( iset  ),
	
	// External A/D Converters
	.ad_cs(  ),
	.ad_sdata_a( 2'b00 ),
	.ad_sdata_b( 2'b00 ),
	.ad_a0(  ),
	.ad_a1(  ),
	.ad_b0(  ),
	.ad_b1(  ),
	.ad_strobe(  ),

	// Input clock
	.clk( clk ),
	.reset( reset )
);

// Free runnig ADC converters
// 12 bit, 4 channel simultaneous, 3 Mhz
adc_module_4ch  _adc (
	// Input clock
	.clk( clk ),
	.reset( reset ),
	// External A/D interface
	.ad_cs( ad_cs ),
	.ad_sdata_a( ad_sdata_a[1:0] ),
	.ad_sdata_b( ad_sdata_b[1:0] ),	
	// ADC held data and strobe
	.ad_a0( ad_a0 ),
	.ad_a1( ad_a1 ),
	.ad_b0( ad_b0 ),
	.ad_b1( ad_b1 ),
	.ad_strobe( ad_strobe )
);

// Modelling Coil Current
// estimate is before sample and 16x finer timing
logic [11:0] iest;
model_coil _model (
	// Input clock
	.clk( clk ),
	.reset( reset ),
	// PWM input
	.pwm( pwm ),
	// Votlage Inputs
	.vcap( ad_a1 ), // ADC voltage across cap
	.vout( ad_b1 ), // ADC voltage across output
	// Current input to rebase estimate
	.iout( ad_a0 ), // Output current
	// Coil Current estimate
	.iest_coil( iest )
);

logic res_val;
logic [11:0] res_calc;
ohm_div _resistance (
	// Input clock
	.clk( clk ),
	.reset( reset ),
	// Votlage and Current Inputs
	.valid_in( ad_strobe ),
	.v_in( ad_b1 ), // ADC Vout
	.i_in( ad_a0 ), // ADC Iout
	// Resistance Output
	.valid_out( res_val ),
	.r_out( res_calc )
);

logic res_pwm;
logic [11:0] igniter_res;
igniter_resistance _res_measurement (
	// Input clock
	.clk( clk ),
	.reset( reset ),
	// Resistance input
	.valid_in( res_val ),
	.r_in( res_calc ),
	// PWM output and enable input
	.pwm( res_pwm ),
	.enable( key == 5'h19 ),
	// Avg Resistance output
	.valid_out( ),
	.r_out( igniter_res )
);

assign pwm = pwm_pulse | res_pwm;

// Digio pads.
	logic [6:0] digio_in, digio_out;
	ioe_pads7 _digio_pads (
		.dout( digio_in ), 
		.din( digio_out ),  
		.pad_io( digio ),
		.oe ( 7'b1101010 ) // Row drive 1653, col sense 204
	);
		
		
// Keyboard Scanner
	key_scan _keypad ( 
		.clk( clk ),
		.reset( reset ),
		.keypad_in( digio_in ),
		.keypad_out( digio_out ),
		.key( key )
	);
	
	

// SPI 8 Memory interface

	logic [7:0] 	spi_data_out;
	logic   			spi_data_oe;
	logic [1:0]   	spi_le_out; // match delay
	logic [7:0] 	spi_data_in;
	logic [1:0]		spi_le_in; // match IO registering
	logic				spi_clk;
	logic				spi_cs;
	logic				spi_rwds_out;
	logic				spi_rwds_oe;
	logic				spi_rwds_in;
	
	// SPI Controller
	
	logic psram_ready;
	logic [17:0] rdata;
	logic [15:0] wdata;
	logic rvalid;
	logic [24:0] araddr;
	logic arvalid, arready;
	logic wready;
	logic [24:0] awaddr;
	logic awvalid;
	logic awready;
	
	// hack view alignment hook
	logic pwm_del;
	logic [15:0] retrigger;
	logic [24:0] base_addr;
	always @(posedge clk) begin
		pwm_del <= pwm;
		retrigger <= ( !pwm_del && pwm && retrigger == 0 ) ? 16'hffff : ( retrigger == 0 ) ? 0 : retrigger - 1;
		base_addr <= ( !pwm_del && pwm && retrigger == 0 ) ? (awaddr - (16 * 64)) : base_addr; // 64 samples before pwm rising edge
	end 
	
	psram_ctrl _psram_ctl(
		// System
		.clk		( clk ),
		.clk4		( clk4 ),
		.reset	( reset ),
		// Psram spi8 interface
		.spi_data_out( spi_data_out ),
		.spi_data_oe(  spi_data_oe  ),
		.spi_le_out( 	spi_le_out 	 ),
		.spi_data_in( 	spi_data_in  ),
		.spi_le_in( 	spi_le_in 	 ),
		.spi_clk( 		spi_clk 		 ),
		.spi_cs( 		spi_cs 		 ),
		.spi_rwds_out( spi_rwds_out ),
		.spi_rwds_oe( 	spi_rwds_oe  ),
		.spi_rwds_in( 	spi_rwds_in  ),
		// Status
		.psram_ready( psram_ready ),	// Indicates control is ready to accept requests
		// AXI4 R/W port
		// Write Data
		.wdata( wdata ),
		.wvalid( 1'b1 ), // always avail)
		.wready( wready ),
		// Write Addr
		.awaddr( awaddr ),
		.awlen( 8'h08 ),	// assumed 8
		.awvalid( awvalid ), // write valid
		.awready( awready ),
		// Write Response
		.bready( 1'b1 ),	// Assume 1, non blocking
		.bvalid( ),
		.bresp(  ),
		// Read Addr
		.araddr( araddr + base_addr ),
		.arlen( 8'h04 ),	// assumed 4
		.arvalid( arvalid ), // read valid	
		.arready( arready ),
		// Read Data
		.rdata( rdata[17:0] ),
		.rvalid( rvalid ),
		.rready( 1'b1 ) // Assumed 1, non blocking
	);	

 	    
	// Capture ID regs 
	logic [35:0] id_reg;
	always @(posedge clk) begin
		id_reg <= ( !psram_ready && rvalid ) ? { id_reg[17:0], rdata[17:0] } : id_reg;
	end
		
	// feedback delay le 2 cycles to match IO
	logic [1:0] 	spi_le_reg;
	always @(posedge clk4) spi_le_reg <= spi_le_out;
	always @(posedge clk4) spi_le_in  <= spi_le_reg;
	
	// Registered I/O pad interfaces
	reg_ioe _spi_d0 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[0] ), .din( spi_data_out[0] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[0] ) );
	reg_ioe _spi_d1 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[1] ), .din( spi_data_out[1] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[1] ) );
	reg_ioe _spi_d2 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[2] ), .din( spi_data_out[2] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[2] ) );
	reg_ioe _spi_d3 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[3] ), .din( spi_data_out[3] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[3] ) );
	reg_ioe _spi_d4 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[4] ), .din( spi_data_out[4] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[4] ) );
	reg_ioe _spi_d5 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[5] ), .din( spi_data_out[5] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[5] ) );
	reg_ioe _spi_d6 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[6] ), .din( spi_data_out[6] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[6] ) );
	reg_ioe _spi_d7 ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_data_in[7] ), .din( spi_data_out[7] ), .oe( spi_data_oe ), .pad_io( spi8_data_pad[7] ) );
	reg_ioe _spi_ds ( .inclock( clk4 ), .outclock( clk4 ), .dout( spi_rwds_in    ), .din( spi_rwds_out    ), .oe( spi_rwds_oe ), .pad_io( spi_ds           ) );
	reg_ioe _spi_clk( .inclock( clk4 ), .outclock( clk4 ), .dout( ),                .din( spi_clk  ),        .oe( 1'b1        ), .pad_io( spi_clk0         ) );
	reg_ioe _spi_ncs( .inclock( clk4 ), .outclock( clk4 ), .dout( ),                .din( !spi_cs  ),        .oe( 1'b1        ), .pad_io( spi_ncs          ) ); // invert CS on output
	reg_ioe _spi_nrst(.inclock( clk4 ), .outclock( clk4 ), .dout( ),                .din( !reset   ),        .oe( 1'b1        ), .pad_io( spi_nrst         ) ); // send out nreset
	

	////////////////////////////////
	//       Data Capture
	////////////////////////////////
	
	// Can capture ALL adc samples, when psram_ready
	// write all samples into the fifo (as burst write of 4 16-bit samples)	
	// When there are 8 words in the fifo, initiate a write 
	// increment the address by 16bytes  = 8x 16bit = 2 samples of 64 bit;
	
			
	// Fifo Write 
	
	logic almost_empty;
	logic [15:0] wrfifo_data;
	logic wrfifo;
	logic [3:0][15:0] ad_data;
	logic [2:0] ad_strobe_d;
	
	always @(posedge clk) begin
		ad_strobe_d <= { ad_strobe_d[1:0], ad_strobe & psram_ready}; 
		if( ad_strobe ) begin
		ad_data <= { { iest[11:8], ad_a0[11:0] },
						 { iest[7:4], ad_a1[11:0] },
						 { iest[3:0], res_calc[11:0] /*ad_b0[11:0]*/ }, // temp override.
						 { 3'h0, pwm, ad_b1[11:0] } };
		end else begin
			ad_data <= ad_data;
		end
	end
	assign wrfifo_data = ( ad_strobe ) ? { iest[11:8], ad_a0[11:0] } :
			               ( ad_strobe_d[0] ) ? ad_data[2] :
			               ( ad_strobe_d[1] ) ? ad_data[1] :
			               ( ad_strobe_d[2] ) ? ad_data[0] : 16'h0048;
	assign wrfifo = (ad_strobe & psram_ready) | (|ad_strobe_d);
	
	adc_mem_fifo  #( 16, 9, 512 ) _write_fifo
	( 
		.clk ( clk ),
		.reset ( reset ),
		// status flags
		.full( ),
		.empty( ),
		.almost_empty( almost_empty ),
		// Input from adc's
		.we( wrfifo ),
		.d( wrfifo_data ),
		// output to write port of psram
		.re( wready ),
		.q( wdata )
	); 
		
	// Fifo Read / PSRAM Write control. 
	// when there are 8 or more (!almost_empty)
	// psram write awaddr and awvalid write request
	// wait for awready
	// increment awaddr address by 16
	// Repeat.
	
	always @(posedge clk) begin
		if( reset ) begin
			awaddr <= 25'b0;
			awvalid <= 0;
		end else begin
			awvalid <= !almost_empty; // race if mem ctrl reads ahead, but not here
			awaddr <= ( awready & awvalid ) ? awaddr + 25'd16 : awaddr;
		end
	end

		
	/////////////////////////////////
	////
	////       VIDEO
	////
	//////////////////////////////////
	
	// HDMI reset
	logic [3:0] hdmi_reg;
	always @(posedge hdmi_clk) begin
		hdmi_reg[3:0] <= { hdmi_reg[2:0], reset };
	end
	logic hdmi_reset;
	assign hdmi_reset = hdmi_reg[3];
	
	
	// XVGA 800x480x60hz sych generator
	logic blank, hsync, vsync;
	vga_800x480_sync _sync
	(
		.clk(   hdmi_clk   ),	
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync )
	);
	
	// Font Generator
	logic [7:0] char_x, char_y;
	logic [255:0] ascii_char;
	logic [15:0] hex_char;
	logic [1:0] bin_char;
	ascii_font57 _font
	(
		.clk( hdmi_clk ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.char_x( char_x ), // 0 to 105 chars horizontally
		.char_y( char_y ), // o to 59 rows vertically
		.hex_char   ( hex_char ),
		.binary_char( bin_char ),
		.ascii_char ( ascii_char )	
	);

	// test pattern gen
	logic [7:0] test_red, test_green, test_blue;
	test_pattern _testgen 
	(
		.clk( hdmi_clk  ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.red	( test_red   ),
		.green( test_green ),
		.blue	( test_blue  )
	);	
	
	//////////////////////
	//////////////////////
   //
	// HDMI #1
   //
   //////////////////////
	//////////////////////
	

	// Process ADC diag looking for 0's and holding till vsync
	// ensures zero's will be seen by the eye. (1/10 sec?)
	logic [3:0] diag_reg, diag;
	logic [21:0] tenth;
	assign diag = { LIdiag, CVdiag, CIdiag, LVdiag }; // A0, A1, B0, B1
	always @(posedge clk) begin
		tenth <= tenth + 1;
		diag_reg <= ( tenth == 0 ) ? diag : diag & diag_reg;
	end

	
	// Average of the adc values
	
	logic [0:3][33:0]  acc	   ; // accumulate 4M x 12 bit samples, 1.3 sec
	logic [0:3][11:0]  avg	   ;
	logic [21:0]       acc_cnt ; // count to 4M
	
	always @(posedge clk) begin
		if( reset ) begin
			acc     <= 0;
			acc_cnt <= 0;
			avg     <= 0;
		end else begin
			if( ad_strobe ) begin
				acc[0] <= ( acc_cnt == 0 ) ? { 22'h00_0000, ad_a0[11:0] } : acc[0] + { 22'h00_0000, ad_a0[11:0] };
				acc[1] <= ( acc_cnt == 0 ) ? { 22'h00_0000, ad_a1[11:0] } : acc[1] + { 22'h00_0000, ad_a1[11:0] };
				acc[2] <= ( acc_cnt == 0 ) ? { 22'h00_0000, ad_b0[11:0] } : acc[2] + { 22'h00_0000, ad_b0[11:0] };
				acc[3] <= ( acc_cnt == 0 ) ? { 22'h00_0000, ad_b1[11:0] } : acc[3] + { 22'h00_0000, ad_b1[11:0] };
				if( acc_cnt == 0 ) begin
					avg[0] <= acc[0][33-:12];
					avg[1] <= acc[1][33-:12];
					avg[2] <= acc[2][33-:12];
					avg[3] <= acc[3][33-:12];	
				end else begin
					avg <= avg;
				end
				acc_cnt <= acc_cnt + 1;
			end else begin
				avg <= avg;
				acc <= acc;
				acc_cnt <= acc_cnt;
			end
		end
	end
		
	// snapshot display values during vsync
	logic [11:0] value_1, value_2, value_3, value_4;
	logic [4:0] key_reg;
	always @(posedge clk) begin
		if( vsync ) begin
			value_1[11:0] <= avg[0]; // ad_a0;
			value_2[11:0] <= avg[1]; // ad_a1;
			value_3[11:0] <= avg[2]; // ad_b0;
			value_4[11:0] <= avg[3]; // ad_b1;
			key_reg <= key;
		end
	end
	
	// Overlay PSRAM ID and expected values
	logic [31:0] disp_id;
	assign disp_id = { id_reg[34:31], id_reg[30:27],id_reg[25:22],id_reg[21:18],id_reg[16:13],id_reg[12: 9],id_reg[ 7: 4],id_reg[ 3: 0] };
	logic [2:0] id_str;
	string_overlay #(.LEN(17)) _id0(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.ascii_char(ascii_char), .x('h10),.y('hC), .out( id_str[0]), .str( "0E960001 Expected" ) );
	hex_overlay    #(.LEN(8 )) _id1(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.hex_char(hex_char), .x('h10),.y('hD), .out( id_str[1]), .in( disp_id ) );
   bin_overlay    #(.LEN(1 )) _id2(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.bin_char(bin_char), .x('h20),.y('hD), .out( id_str[2]), .in( disp_id == 32'h0E96_0001 ) );

	
	// Overlay the Keystroke
	logic key_str, key_strg;
	hex_overlay #(.LEN(1)) _key  (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h1D),.y('h5), .out( key_str  ), .in( key_reg[3:0] ) );
	assign key_strg = key_str & key_reg[4];

	// 4ch Oscilloscope mem & vga display
	logic [7:0] scope_red, scope_green, scope_blue;
	vga_scope _scope(
		.clk(   hdmi_clk ),
		.reset( reset ),
		// video sync 
		.blank( blank ), 
		.hsync( hsync ),
		.vsync( vsync ),
		// Font data
		.ascii_char( ascii_char ),
		.hex_char( hex_char ),
		.bin_char( bin_char ),
		.char_x( char_x ),
		.char_y( char_y ),
		// capture inputs
		.ad_a0( ad_a0 ),
		.ad_a1( ad_a1 ),
		.ad_b0( ad_b0 ),
		.ad_b1( ad_b1 ),
		.ad_strobe( ad_strobe ),
		.ad_clk( clk ),
		// video output
		.red(   scope_red ),
		.green( scope_green ),
		.blue(  scope_blue )
	);
	
	// 12 bit resistance number is 6.5. so 
	// plotting as 8.4 with { 2`b00, in[10:1] } will give Ohms. A decimal point woudl be nice
	logic res_str;
	hex_overlay #(.LEN(3)) _res  (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h1B),.y('h13), .out( res_str   ), .in( { 2'b00, ~igniter_res[10:1] } ) );
	
	// 12bit hex overlays(4)
	logic [3:0] hex_str;
	hex_overlay #(.LEN(3)) _hex0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h1B),.y('h15), .out( hex_str[0]), .in( value_1 ) );
	hex_overlay #(.LEN(3)) _hex1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h1B),.y('h17), .out( hex_str[1]), .in( value_2 ) );
	hex_overlay #(.LEN(3)) _hex2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h1B),.y('h19), .out( hex_str[2]), .in( value_3 ) );
	hex_overlay #(.LEN(3)) _hex3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h1B),.y('h1B), .out( hex_str[3]), .in( value_4 ) );
					
	// dump binary	values	
	logic [3:0] bin_str;
	bin_overlay #(.LEN(12)) _bin0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h20), .y('h15), .out( bin_str[0] ), .in( value_1 ) );
	bin_overlay #(.LEN(12)) _bin1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h20), .y('h17), .out( bin_str[1] ), .in( value_2 ) );
	bin_overlay #(.LEN(12)) _bin2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h20), .y('h19), .out( bin_str[2] ), .in( value_3 ) );
	bin_overlay #(.LEN(12)) _bin3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h20), .y('h1B), .out( bin_str[3] ), .in( value_4 ) );

	
	// Dump Diag bits
	logic [3:0] diag_str;
	bin_overlay #(.LEN(1)) _diag0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h16), .y('h15), .out( diag_str[0] ), .in( diag_reg[3] ) );
	bin_overlay #(.LEN(1)) _diag1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h16), .y('h17), .out( diag_str[1] ), .in( diag_reg[2] ) );
	bin_overlay #(.LEN(1)) _diag2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h16), .y('h19), .out( diag_str[2] ), .in( diag_reg[1] ) );
	bin_overlay #(.LEN(1)) _diag3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h16), .y('h1B), .out( diag_str[3] ), .in( diag_reg[0] ) );
	
	// Merge overlays
	logic overlay;
	assign overlay = (|diag_str) | 
	                 (|bin_str ) |
						  (|hex_str ) |
						  ( key_strg) |
						  ( res_str ) |
						  (|id_str  ) ;
	
	// video encoder
	logic [7:0] hdmi_data;
	video_encoder _encode
	(
		.clk(  hdmi_clk  ),
		.clk5( hdmi_clk5 ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.red	( test_red   | {8{overlay}} | scope_red   ),
		.green( test_green | {8{overlay}} | scope_green ),
		.blue	( test_blue  | {8{overlay}} | scope_blue  ),
		.hdmi_data( hdmi_data )
	);	
	
	hdmi_out _hdmi_out ( // LDVS DDR outputs
		.outclock( hdmi_clk5 ),
		.din( hdmi_data ),
		.pad_out( {hdmi_d2, hdmi_d1, hdmi_d0, hdmi_ck} ), 
		.pad_out_b( )  // true differential, _b not req
	);
	
	

	//////////////////////
	//////////////////////
   //
	// HDMI #2
   //
   //////////////////////
	//////////////////////


	
	// Oscilloscope & vga display
	logic [7:0] wave_scope_red, wave_scope_green, wave_scope_blue;
	vga_wave_display _wave_scope (
		.clk(   hdmi_clk ),
		.reset( reset ),
		// video sync 
		.blank( blank ), 
		.hsync( hsync ),
		.vsync( vsync ),
		// Font data
		.ascii_char( ascii_char ),
		.char_x( char_x ),
		.char_y( char_y ),
		// AXI Sram Read port connection
		.psram_ready	( psram_ready 	 ) ,
		.rdata			( rdata 			 ) , 
		.rvalid			( rvalid		    ) ,
		.araddr			( araddr[24:0]	 ) ,
		.arvalid			( arvalid		 ) , 
		.arready			( arready		 ) ,
		.mem_clk			( clk ),
		// video output
		.red(   wave_scope_red ),
		.green( wave_scope_green ),
		.blue(  wave_scope_blue )	
	);	

	// video encoder
	logic [7:0] hdmi2_data;
	video_encoder _encode2
	(
		.clk  ( hdmi_clk  ),
		.clk5 ( hdmi_clk5 ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		.red	( wave_scope_red   ),
		.green( wave_scope_green ),
		.blue	( wave_scope_blue  ),
		.hdmi_data( hdmi2_data )
	);

	// HDMI Output, DDR outputs
	hdmi_out _hdmi2_out ( // LDVS DDR outputs
		.outclock( hdmi_clk5 ),
		.din( hdmi2_data ),
		.pad_out( {hdmi2_d2, hdmi2_d1, hdmi2_d0, hdmi2_ck} ), 
		.pad_out_b( )  // true differential, _b not req
	);
	
endmodule

module key_scan( 
	input [6:0] keypad_in,
	output [6:0] keypad_out,
	input	clk,
	input reset,
	output [4:0] key
	);
	
	
	logic [11:0] div;
	logic [2:0] col;
	logic [3:0] row;
	logic flag;
	always @(posedge clk) begin
		if( reset ) begin
			key <= 0;
			div <= 0;
			col <= 0;
			row <= 0;
			flag <= 0;
			keypad_out <= 0;
		end else begin
			div <= div + 1;
			// drive 4 rows
			keypad_out[1] <= ( div[11:10] == 0 ) ? 1'b0 : 1'b1;
			keypad_out[6] <= ( div[11:10] == 1 ) ? 1'b0 : 1'b1;
			keypad_out[5] <= ( div[11:10] == 2 ) ? 1'b0 : 1'b1;
			keypad_out[3] <= ( div[11:10] == 3 ) ? 1'b0 : 1'b1;
			// capture columns
				if( div[11:0] == 0 ) begin
					flag <= 0;
					col <= col;
					row <= row;
				end else if( div[11:0] == 12'hfff && flag == 0 ) begin
					col <= 0;
					row <= 0;
				end else if( div[9:0] == 10'h3F0 && { keypad_in[2], keypad_in[0], keypad_in[4]} != 3'b111 ) begin // key pressed
					flag  <= 1;
					col[2] <= !keypad_in[2];
					col[1] <= !keypad_in[0];
					col[0] <= !keypad_in[4];
					row[0] <= !keypad_in[1];
					row[1] <= !keypad_in[6];
					row[2] <= !keypad_in[5];
					row[3] <= !keypad_in[3];
				end else begin
					flag <= flag;
					col <= col;
					row <= row;
				end
			key <= ( col[2:0] == 3'b001 && row[0] ) ? 5'h13 :
					 ( col[2:0] == 3'b001 && row[1] ) ? 5'h16 :
					 ( col[2:0] == 3'b001 && row[2] ) ? 5'h19 :
					 ( col[2:0] == 3'b001 && row[3] ) ? 5'h1B :
					 ( col[2:1] == 3'b01  && row[0] ) ? 5'h12 :
					 ( col[2:1] == 3'b01  && row[1] ) ? 5'h15 :
					 ( col[2:1] == 3'b01  && row[2] ) ? 5'h18 :
					 ( col[2:1] == 3'b01  && row[3] ) ? 5'h10 :
					 ( col[2  ] == 3'b1   && row[0] ) ? 5'h11 :
					 ( col[2  ] == 3'b1   && row[1] ) ? 5'h14 :
					 ( col[2  ] == 3'b1   && row[2] ) ? 5'h17 :
					 ( col[2  ] == 3'b1   && row[3] ) ? 5'h1A : 5'h00;		
		end
	end	
endmodule