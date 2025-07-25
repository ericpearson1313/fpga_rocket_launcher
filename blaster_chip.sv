
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

trial_pll _spll(
	.inclk0 (clk_in),		// External clock input
	.c0     (clk_out), 	// Flash Clock 6Mhz, also External clock output differential
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



// Rs232 loopback
assign tx232 = rx232;
// LEDs active low
logic arm_led;
logic cont_led;
assign arm_led_n = arm_led;	// not complemented bc external NPN
assign cont_led_n = cont_led; //  we added a NPN  to drive 12v led
assign speaker_n = !speaker;

// AIN
assign anain[3:1] = iset[2:0]; // active low switch inputs
assign anain[4] = !reset;
logic [24:0] count;
always @(posedge clk) begin
	count <= count + 1;
end
assign anain[8:5] = count[24:21];
assign anain[8]=count[24];

// ADC Scale parameters
parameter ADC_VOLTS_PER_DN = 0.2005;
parameter ADC_DN_PER_AMP = 205;
// Physical parameters
parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
parameter COIL_IND_UH = 390;
	
//`define FORGE_EMULATOR
`ifdef FORGE_EMULATOR
/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
//
//                 FORGE EMULATOR <start>
//

// Signals Tied Off during emulation
logic [43:0] eout = 0;
logic [43:0] ecap = 0;

// Emulation data for display
logic 			burn;				
logic [11:0] 	ad_a0, ad_a1, ad_b0, ad_b1;
logic 			ad_strobe;
logic	[11:0]	iest;	
logic	[11:0]	igniter_res;
// Emulation display control signals
logic 			scroll_halt;	// scroll is halted after discharge
logic 			charge;			// HDMI is held in reset during chargin
logic				fire_done;		// Changes fire button function
logic				fire_button_debounce; // Debounced fire button for zoom
logic 			cap_halt;		// disables 4M buffer capture
logic				long_fire;		// turns on blipvert


	
	forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) _uut (
		// System
		.clk				( clk ),
		.reset			( 1'b0 ),//reset ),
		// Front Panel
		.fire_button 	( fire_button ),
		.arm_led 		( arm_led ),
		.cont_led 		( cont_led ),
		.speaker 		( speaker ),
		// High Voltage
		.lt3420_charge ( lt3420_charge ),
		.lt3420_done   ( lt3420_done   ),
		.pwm           ( pwm ),
		.dump				( dump ),
		// ADC interface
		.ad_cs			( ad_cs ),
		.ad_sdata_a 	( ad_sdata_a ),
		.ad_sdata_b 	( ad_sdata_b ),
		
		// Emulation interconnectes
		// Tied off Debug inputs
		.iset				( 3'b011 ),//iset ),
		.key				( 5'b00000 ),//key ),
		// Internal Logging outputs
		.ad_a0			( ad_a0 ) , 
		.ad_a1         ( ad_a1 ), 
		.ad_b0         ( ad_b0 ), 
		.ad_b1         ( ad_b1 ),
		.ad_strobe     ( ad_strobe ),
		.iest          ( iest ),
		.burn          ( burn ),
		.igniter_res	( igniter_res ),
		// intenal logging control signals
		.scroll_halt	( scroll_halt ),
		.charge			( charge ),
		.fire_done		( fire_done ),
		.fire_button_debounce ( fire_button_debounce ),
		.cap_halt		( cap_halt ),
		.long_fire		( long_fire )

   );




//
//                 FORGE EMULATOR <end>
//
/////////////////////////////////////////////////////////////////////////////////
/////////////////////////////////////////////////////////////////////////////////
`else // FORGE EMULATOR


//////////////////////////////////////////////
// fire button 10ms debounce 
// signal to get 1.3 sec of pwm current control
// signal One shot capture mode on 1st rising pwm edge 1.3 sec
// signal to set discharge at 1.3sec
// signal to stop tiny scroll window at 4.3 sec
//////////////////////////////////////////////

logic [27:0] fire_count; 
logic fire_flag;
logic fire_done ; // self discharge 
logic scroll_halt;
logic cap_halt; // full rate capture
logic fire_button_debounce;
logic long_fire; // fire button held down >1 wsec

debounce _firedb ( .clk( clk ), .reset( reset ), .in( fire_button ), .out( fire_button_debounce ), .long( long_fire ));

parameter PWM_START     = 1; // Enable PWM current control 
parameter PWM_END			= (48+16) * 1000 * 1000; // Total time 1.333 sec
parameter SCROLL_HALT	= (48*4+16) * 1000 * 1000; // Total time 1.333 sec
parameter CAP_HALT		= PWM_START + 1000 * 16; // stop capture before re-trigger or wrap

always @(posedge clk) begin
	if( reset ) begin // for now, later should allow arm release
		fire_count <= 0;
		fire_flag <= 0;
		fire_done <= 0;
		scroll_halt <= 0;
		cap_halt <= 0;
	end else begin
		fire_count <= ( fire_count == 0 && !fire_button_debounce ) ? 0 : fire_count + 1; // committed when past debounce
		fire_flag <= ( fire_count == PWM_START && !fire_done ) ? 1'b1 : ( fire_count == PWM_END ) ? 1'b0 : fire_flag;
		scroll_halt <= ( fire_count == SCROLL_HALT ) ? 1'b1 : scroll_halt;
		cap_halt <= ( fire_count == CAP_HALT ) ? 1'b1 : cap_halt;
		fire_done <= ( fire_count == PWM_END ) ? 1'b1 : fire_done;
	end
end

assign dump = fire_done  | key == 5'h1B; // always dump after firing

////////////////////////////////
// Power On auto charge and continuity until fire button
////////////////////////////////

logic charge;  // charge cap flag
logic continuity; // test cont flag
always @( posedge clk ) begin
	if( reset ) begin
		charge <= !iset[2]; //Latch on reset
		continuity <= 0;
	end else begin
		if( lt3420_done && charge ) begin // switch to continuity
			charge <= 0;
			continuity <= 1;
		end else if( continuity && fire_flag 
		) begin
			charge <= 0;
			continuity <= 0;
		end else begin
			charge <= charge;
			continuity <= continuity;	
		end
	end
end

assign lt3420_charge = charge | key == 5'h1A;


//////////////////////////////



// Speaker is differential out gives 6Vp-p
logic [15:0] tone_cnt;
logic cont_tone, first_tone;
logic spk_en, spk_toggle;

always @(posedge clk) begin
	if( tone_cnt == 0 ) begin
		spk_toggle <= !spk_toggle;
		{spk_en, tone_cnt}<= ( key == 5'h11 || fire_button_debounce ) ? { 1'b1, 16'h2CCA } :
								   //( key == 5'h12 ) ? { 1'b1, 16'h27E7 } :
								   ( key == 5'h13 ) ? { 1'b1, 16'h238D } :
								   //( key == 5'h14 ) ? { 1'b1, 16'h218E } :
								   ( key == 5'h15 ) ? { 1'b1, 16'h1DE5 } :
								   //( key == 5'h16 ) ? { 1'b1, 16'h1AA2 } :
								   //( key == 5'h17 ) ? { 1'b1, 16'h17BA } :
								   ( /*key == 5'h18 ||*/ ( (cont_tone && !iset[0]) || first_tone ) ) ? { 1'b1, 16'h1665 } : 0; // sw0 mutes tone
	end else begin
		tone_cnt <= tone_cnt - 1;
		spk_en <= spk_en;
		spk_toggle <= spk_toggle;
	end
end

assign speaker = spk_toggle & spk_en ; 



////////////////////////////////////////////
// Burn-through detect 
// to detect when the current falls to zero during the fire_flag while still have remaining cap voltage.
// Output voltage is expected to rise to cap voltage. This will happen after current rise.
// After observation the real indication is output voltage rise rate at burnthrough, or open circuit.
 
logic burn;
logic current_seen;
logic [11:0] ad_b1_del;
logic signed [12:0] dv; // delta voltage

assign dv[12:0] = { ad_b1[11], ad_b1[11:0] ^ 12'h7ff } - { ad_b1_del[11], ad_b1_del[11:0] ^ 12'h7ff };

always @(posedge clk) begin
	if( reset ) begin
		burn <= 0;
		current_seen <= 0;
		ad_b1_del <= 12'h7ff;
	end else begin
		current_seen <= ( fire_flag && (!ad_a0[11] && ((ad_a0 ^ 12'h7FF) > (100)))) ? 1'b1 : current_seen; // current > 1/2 Amp seen
		burn <=((( ad_a0[11] || ((ad_a0 ^ 12'h7FF) < (32)) || (((ad_b1 ^ 12'h7ff) > (ad_a1 ^ 12'h7ff))&&!ad_b1[11]&&!ad_a1[11]) ) && // output current < 1/6 amp || output voltage > cap voltage
					(!ad_a1[11] && ((ad_a1 ^ 12'h7ff) > (256))) && // cap voltage > 50 Volts 
					current_seen && fire_flag ) || 
					//( fire_flag && (!ad_a0[11]&&((ad_a0 ^ 12'h7ff) > ( 205 * 6 )))) || // temp trigger for 6A
				   ( fire_flag && ( dv > 13'sd40 ))	// dv > +24 V/us
					) ? 1'b1 : burn; 
		ad_b1_del <= ad_b1; // ad_b1 only changes on sample x16, but is fine for our detection use
		//burn <= ( fire_flag && ( dv > 13'sd50 ) ) ? 1'b1 : burn; // rise rate > 10V/sample == 30 V/usec
	end
end

////////////////////////////////////////////
// PWM Current limited pulse generator
////////////////////////////////////////////
logic [11:0] ad_a0, ad_a1, ad_b0, ad_b1;
logic ad_strobe;
logic [11:0] 	iest;
logic 			pwm_pulse;
logic [15:0] 	pulse_time;
logic [9:0] 	pulse_count;
logic				ramp_flag;

logic [11:0] 	thresh_hi, thresh_lo;

parameter COUNT_10MS = 28'h00_80000; // 10ms / CLOCK_FREQ_MHZ
parameter COUNT_20MS = 28'h01_00000; // 20ms / CLOCK_FREQ_MHZ

always @(posedge clk) thresh_hi <= (fire_flag && fire_count < COUNT_10MS ) ? ( ADC_DN_PER_AMP * 2 + 20 ) : // until 10ms setpoint 2Amp 
											  (fire_flag && fire_count < COUNT_20MS ) ? ( ADC_DN_PER_AMP * 4 + 20 ) : // until 20ms setpoint 4amp
											                           /* remainder */  ( ADC_DN_PER_AMP * 6 + 20 ) ; // remainder  setpoint 6Amp
always @(posedge clk) thresh_lo <= (fire_flag && fire_count < COUNT_10MS ) ? ( ADC_DN_PER_AMP * 2 - 20 ) : 
											  (fire_flag && fire_count < COUNT_20MS ) ? ( ADC_DN_PER_AMP * 4 - 20 ) : 
											                           /* remainder */  ( ADC_DN_PER_AMP * 6 - 20 ) ;

always @(posedge clk) begin
	if( reset ) begin
		pwm_pulse <= 0;
		pulse_time <= 0;
		pulse_count <= 0;
		ramp_flag <= 0;
	end else begin
		if( pwm_pulse ) begin // turn off pulse if time or current level exceeded
			if( pulse_time < 32 ) begin // min pulse width
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count	
				ramp_flag <= ramp_flag;
			end else if(( burn )																	// burnthrough
			         || ( pulse_time >= (48  * 16))    									// usec @ 48 Mhz 
						||	( !ad_a0[11] && ((ad_a0 ^ 12'h7FF) > (thresh_hi)))		// measure iout > 2.2 amps (panic only?)
						||	( !iest[11]  && ((iest  ^ 12'h7ff) > (thresh_hi)) && iset[1] )	// est iout > 2.2 amps, disable est use, fb only
						) begin //  >2 amp * 205 DN/A measured + 10%
				pwm_pulse <= 0;
				pulse_time <= 0;
				pulse_count <= pulse_count - 1;
				ramp_flag <= ramp_flag;
			end else begin
				ramp_flag <= ramp_flag;
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count
			end
		end else if( !burn && !pwm_pulse && ( fire_flag || pulse_count > 0 ) ) begin // wait for ad_a0 to fall
			if( pulse_time < (48 * 4) ) begin // min pulse width
				ramp_flag <= ramp_flag;
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count					
			end else if ( ( ad_a0[11] || ((ad_a0 ^ 12'h7FF) < (thresh_lo))) ) begin //  <2 amp * 205 DN/A measured - 10%
				ramp_flag <= ramp_flag;
				pwm_pulse <= 1;
				pulse_time <= 1;
				pulse_count <= pulse_count;
			end else begin // current above min tolerance
				ramp_flag <= 0;  // cleared now meeting min tolerage
				pwm_pulse <= 0;
				pulse_time <= pulse_time + 1; 
				pulse_count <= pulse_count;
			end			
		end else if( ( key == 5'h10) && count[15:0] == 0 ) begin // (re)Triggered by fire key at 64k/48Mhz=1.3ms period
			ramp_flag <= 1; // short back to back pulses
			pwm_pulse <= 1; // Set pwm output
			pulse_time <= 1; // start max width counter
			pulse_count <= 30; // two pulses
		end else begin // await trigger
			ramp_flag <= 1;
			pwm_pulse <= 0;
			pulse_time <= 0;		
			pulse_count <= 0;
		end
	end
end


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
logic res_flag;
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
	.enable( key == 5'h19 || continuity ),
	// Avg Resistance output
	.valid_out( ),
	.r_out( igniter_res ),
	// Tone and LED output
	.tone( cont_tone ),
	.first_tone( first_tone ),
	.led( cont_led ),
	.energy( res_flag )
);

assign pwm = pwm_pulse | res_pwm;

// Arm is based on vcap with 300v on thresh and 50v off thresh
logic cap_charged;
always @( posedge clk ) begin
	if( reset ) begin
		cap_charged <= 0;
	end else begin
		cap_charged <= ( strobe_d && vcap > (( 300 * 10000 ) / 2005 ) ) ? 1'b1 :
		               ( strobe_d && vcap < (( 50  * 10000 ) / 2005 ) ) ? 1'b0 : cap_charged;
	end
end

assign arm_led = cap_charged | ( charge && count[24:21] == 0 );

// Energy Accumulators
// Accululated during fire_flag | res_flag.
logic [43:0] eout, ecap; // accumulated cap energy and output energy as 44 bits
logic acc_flag, acc_flag_d, strobe_d;
logic [21:0] pout, pcap; // instantaneous power
logic [10:0] vout, vcap, iout, icap;

// clip inputs to +ve
assign vout = ( ad_b1[11] || ad_b1[10:4] == 7'h7F ) ? 11'b0 : ( ad_b1[10:0] ^ 11'h7FF );
assign vcap = ( ad_a1[11] || ad_a1[10:4] == 7'h7F ) ? 11'b0 : ( ad_a1[10:0] ^ 11'h7ff );
assign iout = ( ad_a0[11] || ad_a0[10:4] == 7'h7F ) ? 11'b0 : ( ad_a0[10:0] ^ 11'h7ff );
assign icap = ( ad_b0[11] || ad_b0[10:4] == 7'h7F ) ? 11'b0 : ( ad_b0[10:0] ^ 11'h7ff );

// accumulate during fire pulse or individual continuity test pulses
assign acc_flag = ( fire_flag & !burn ) | res_flag;

// Acculuate both Cap and Output power products.
always @(posedge clk) begin
	strobe_d <= ad_strobe;
	// P = I * V
   pout[21:0] <= vout[10:0] * iout[10:0];
   pcap[21:0] <= vcap[10:0] * icap[10:0];
	if( strobe_d ) begin
		acc_flag_d <= acc_flag;
		// raw power loaded at flag rise, acculuated during flag, and held afterwards
		eout[43:0] <= ( acc_flag && !acc_flag_d ) ? { 22'b0, pout[21:0] } : ( acc_flag ) ? ({ 22'b0, pout[21:0] } + eout[43:0]) : eout[43:0];
		ecap[43:0] <= ( acc_flag && !acc_flag_d ) ? { 22'b0, pcap[21:0] } : ( acc_flag ) ? ({ 22'b0, pcap[21:0] } + ecap[43:0]) : ecap[43:0];
	end else begin
		acc_flag_d <= acc_flag_d;
		eout[43:0] <= eout[43:0];
		ecap[43:0] <= ecap[43:0];
	end
end

`endif // FORGE_EMULATOR

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
	logic pwm_del, burn_del, zoom_del;
	logic [15:0] retrigger;
	logic [24:0] base_addr;
	logic [24:0] burn_addr;
	logic [3:0] zoom;
	logic zoom_button;
	logic key_del;

	
	always @(posedge clk) begin
		if( reset ) begin
			zoom <= 0;
			zoom_button <= 0;
			key_del <= 0;
		end else begin
			key_del <= key[4];
			zoom_button <= ( fire_done &  fire_button_debounce ) ? 1'b1 : 1'b0;
			zoom_del <= zoom_button;
			pwm_del <= pwm;
			burn_del <= burn;
			retrigger <= ( !pwm_del && pwm && retrigger == 0 ) ? 16'hffff : ( retrigger == 0 ) ? 0 : retrigger - 1;
			base_addr <= ( !pwm_del && pwm && retrigger == 0 && !cap_halt ) ? awaddr : base_addr; 
			burn_addr <= ( !pwm_del && pwm && retrigger == 0 && !cap_halt ) ? awaddr : // default to base addr
			             ( !burn_del && burn                              ) ? awaddr : // snap to burn addr
							 ( !key_del && key == 5'h16                       ) ? burn_addr + (512<<zoom) :
							 ( !key_del && key == 5'h14                       ) ? burn_addr - (512<<zoom) :
							                                                      burn_addr;
			zoom <= ( !zoom_del && zoom_button || !key_del && key == 5'h12 ) ? ( ( zoom == 12 ) ? 0 : zoom + 1 ) : 
					  (                             !key_del && key == 5'h18 ) ? ( ( zoom == 0 ) ? 11 : zoom - 1 ) : zoom;
		end
	end 
	
	// bv raddr bus 
	logic [24:0] 	bv_araddr;
	logic [7:0]  	bv_arlen; // always == 8'd32
	logic        	bv_arvalid;
	logic 		 	bv_arready;
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
		// Read Addr, Port 0, bl=4
		.araddr0 ( burn_addr + ( araddr << zoom ) - (((burn)?(192*16):(64*16))<<zoom) ),
		.arlen0  ( 8'd04 ),	// assumed 4
		.arvalid0( arvalid ), // read valid	
		.arready0( arready ),
		// Read Addr, Port 1, bl = 32
		.araddr1 ( bv_araddr ),
		.arlen1  ( bv_arlen ),	// assumed 32
		.arvalid1( bv_arvalid ), // read valid	
		.arready1( bv_arready ),
		// Read Data, shared
		.rdata( rdata[17:0] ),
		.rvalid( rvalid ),
		.rready( 1'b1 ) // Assumed 1, non blocking
	);	

 	    
	// Capture ID regs 
	//logic [35:0] id_reg;
	//always @(posedge clk) begin
	//	id_reg <= ( !psram_ready && rvalid ) ? { id_reg[17:0], rdata[17:0] } : id_reg;
	//end
		
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
						 { iest[3:0], ad_b0[11:0] /*res_calc[11:0]*/ }, // temp override.
						 { 1'b0, fire_button, burn, pwm, ad_b1[11:0] } };
		end else begin
			ad_data <= ad_data;
		end
	end
	assign wrfifo_data = ( ad_strobe ) ? { iest[11:8], ad_a0[11:0] } :
			               ( ad_strobe_d[0] ) ? ad_data[2] :
			               ( ad_strobe_d[1] ) ? ad_data[1] :
			               ( ad_strobe_d[2] ) ? ad_data[0] : 16'h0048;
	assign wrfifo = (ad_strobe & psram_ready) | (|ad_strobe_d);
	
	adc_fifo _write_fifo
	(
	.clock( clk ),
	.almost_empty( almost_empty ),
	.wrreq( wrfifo ),
	.data( wrfifo_data ),
	.rdreq( wready ),
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
			if( cap_halt && awaddr[24:4] == (base_addr[24:4] - 16384) ) begin // approx 10 ms before start
				awvalid <= 0;
				awaddr <= awaddr;
			end else begin
				awvalid <= !almost_empty; // race if mem ctrl reads ahead, but not here
				awaddr <= ( awready & awvalid ) ? awaddr + 25'd16 : awaddr;
			end
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
	
	logic video_preamble;
	logic data_preamble;
	logic video_guard;
	logic data_guard;
	logic data_island;
	
	// XVGA 800x480x60hz sych generator
	logic blank, hsync, vsync;
	vga_800x480_sync _sync
	(
		.clk(   hdmi_clk   ),	
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		// HDMI encoding controls
		.video_preamble( video_preamble ),
		.data_preamble ( data_preamble  ),
		.video_guard   ( video_guard    ),
		.data_guard    ( data_guard     ),
		.data_island   ( data_island    )
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
	
	// Flash Memory interface (init font and text overlay)
	// the serial interface runs at 6 Mhz (max 7 Mhz!)
	// we assigned c0 the output diff pair clock to this interface.
	
	logic [11:0] 	flash_addr; // 32 bit word address, 16Kbytes total flash for M04
	logic 			flash_read;
	logic				flash_data;
	logic 			flash_wait;
	logic 			flash_valid;
	ufm_flash _flash (
		.clock						( clk_out 			 ), // 6 Mhz
		.avmm_data_addr			( flash_addr[11:0] ), // word address 
		.avmm_data_read			( flash_read 		 ),
		.avmm_data_readdata		( flash_data 		 ),
		.avmm_data_waitrequest	( flash_wait 		 ),
		.avmm_data_readdatavalid( flash_valid 		 ),
		.avmm_data_burstcount	( 128 * 32 			 ), // 4K bit burst
		.reset_n						( !reset 			 )
	);	
	
	// Text Overlay 
	logic text_ovl;
	logic [3:0] text_color;
	text_overlay _text
	(
		.clk( hdmi_clk  ),
		.reset( reset ),
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		// Overlay output bit for ORing
		.overlay( text_ovl ),
		.color( text_color ),
		// Avalon bus to init font and text rams
		.flash_clock( clk_out 			 ), // 6 Mhz
		.flash_addr ( flash_addr[11:0] ), // word address 
		.flash_read ( flash_read 		 ),
		.flash_data ( flash_data 		 ),
		.flash_wait ( flash_wait 		 ),
		.flash_valid( flash_valid 		 )
	);

	/////////////////////////////////////////////////////
	// BlipVert, 1sec dump of 32M sram on HDMI video out
	/////////////////////////////////////////////////////
	
	// clock crossing of blank
	logic [1:0] bvena;
	always @(posedge clk) bvena[1:0] <= { bvena[0], !blank };	
	
	logic [16:0] bv_wdata;
	logic        bv_wvalid;
	logic blipvert;
	
	assign blipvert = ( key == 5'h17 || long_fire ) ? 1'b1 : 1'b0;
	
	blipvert _bv_unit (
		// System
		.clk		( clk ),
		.reset	( reset ),
		// enable input
		.enable	( bvena[1] & blipvert ), // Rising edge starts
		.base( base_addr[24:0] ), // starting addr to flag first 1k block
		// Psram Port
		.araddr	( bv_araddr ), 
		.arlen 	( bv_arlen  ), // bv uses 32 always
		.arvalid	( bv_arvalid ), // read valid	
		.arready	( bv_arready ),
		.rdata	( rdata[17:0] ), 
		.rvalid	( rvalid ),
		// Output data 
		.vdata	( bv_wdata ),
		.vvalid	( bv_wvalid )
	);
		
	
	// Clock domain crossing fifo 17bit wide
	logic [16:0] bv_vdata;
	logic        bv_vvalid_n; // inverse valid
	logic [30:0] blank_delay;
	logic 		 read_fifo;
	
	always @(posedge hdmi_clk) // Delay reading to allow starting the fill
		{ read_fifo, blank_delay } <= { blank_delay, !blank };
		
	bvfifo _bv_fifo (
		// Write port
		.wrclk	( clk ),
		.wrreq	( bv_wvalid ),
		.data		( bv_wdata[16:0] ),
		// Read port
		.rdclk	( hdmi_clk ),
		.rdreq	( !bv_vvalid_n & read_fifo ), // auto read when not emptyu
		.rdempty	( bv_vvalid_n ),
		.q			( bv_vdata[16:0] )
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
	//assign disp_id = { id_reg[34:31], id_reg[30:27],id_reg[25:22],id_reg[21:18],id_reg[16:13],id_reg[12: 9],id_reg[ 7: 4],id_reg[ 3: 0] };
	logic [4:0] id_str;
	//string_overlay #(.LEN(5)) _id0(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.ascii_char(ascii_char), .x('h48), .y('h09), .out( id_str[0]), .str( "PSRAM" ) );
	//hex_overlay    #(.LEN(8 )) _id1(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.hex_char(hex_char), .x('h50),.y('d58), .out( id_str[1]), .in( disp_id ) );
   //bin_overlay    #(.LEN(1 )) _id2(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.bin_char(bin_char), .x('h46),.y('h09), .out( id_str[2]), .in( disp_id == 32'h0E96_0001 ) );
	//string_overlay #(.LEN(12)) _id3(.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y),.ascii_char(ascii_char), .x('d120),.y('d59), .out( id_str[3]), .str( "ERIC PEARSON" ) );
	string_overlay #(.LEN( 9)) _id4 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h02),.y('h03), .out(id_str[4]), 
	.str(	( zoom == 0 ) ? " 21us/div" :
			( zoom == 1 ) ? " 43us/div" :
			( zoom == 2 ) ? " 85us/div" :
			( zoom == 3 ) ? "170us/div" :
			( zoom == 4 ) ? "340us/div" :
			( zoom == 5 ) ? "680us/div" :
			( zoom == 6 ) ? "1.4ms/div" :
			( zoom == 7 ) ? "2.7ms/div" :
			( zoom == 8 ) ? "5.5ms/div" :
			( zoom == 9 ) ? " 11ms/div" :
			( zoom == 10) ? " 22ms/div" :
			( zoom == 11) ? " 44ms/div" :
			/*zoom == 12)*/ " 87ms/div" ) );

	
	// Overlay the Keystroke
	logic key_str, key_strg;
	hex_overlay #(.LEN(1)) _key  (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x(1),.y(58), .out( key_str  ), .in( key_reg[3:0] ) );
	assign key_strg = key_str & key_reg[4];

	// 4ch Oscilloscope mem & vga display
	logic [7:0] scope_red, scope_green, scope_blue;

	//vga_scope _scope(
	//	.clk(   hdmi_clk ),
	//	.reset( reset ),
	//	// video sync 
	//	.blank( blank ), 
	//	.hsync( hsync ),
	//	.vsync( vsync ),
	//	// Font data
	//	.ascii_char( ascii_char ),
	//	.hex_char( hex_char ),
	//	.bin_char( bin_char ),
	//	.char_x( char_x ),
	//	.char_y( char_y ),
	//	// capture inputs
	//	.ad_a0( ad_a0 ),
	//	.ad_a1( ad_a1 ),
	//	.ad_b0( ad_b0 ),
	//	.ad_b1( ad_b1 ),
	//	.ad_strobe( ad_strobe ),
	//	.ad_clk( clk ),
	//	// video output
	//	.red(   scope_red ),
	//	.green( scope_green ),
	//	.blue(  scope_blue )
	//);
	
	// 4ch Oscilloscope mem & vga display
	logic [7:0] tiny_red, tiny_green, tiny_blue;
	logic tiny;
	tiny_scope #( 
		.V_HEIGHT( 192 ), // 96 or 192 options
		.V_START ( 80  ),
		.H_START	( 480 ),
		.H_END 	( 784 ),
		.N       ( 2   ), // 60 Hz frames per col pel
		.GD_COLOR( 24'h32006a /* smpte_deep_violet */ ), 
		.BG_COLOR( 24'h00214c /* smpte_oxford_blue */ ) //24'h1d1d1d /* smpte_eerie_black */ )	
	 ) _tiny_scope(
		.clk(   hdmi_clk ),
		.reset( reset ),
		// video sync 
		.blank( blank ), 
		.hsync( hsync ),
		.vsync( vsync ),
		// scroll halt input
		.halt ( scroll_halt ),
		// capture inputs
		.ad_a0( ad_a0 ),
		.ad_a1( ad_a1 ),
		.ad_b0( ad_b0 ),
		.ad_b1( ad_b1 ),
		.ad_strobe( ad_strobe ),
		.ad_clk( clk ),
		// video output
		.red(   tiny_red ),
		.green( tiny_green ),
		.blue(  tiny_blue )
	);
	assign tiny = |{ tiny_red, tiny_green, tiny_blue };
	
	
	// Energy accumulator
	logic [7:0] pwr_str;
	string_overlay #(.LEN(8)) _pwr0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d100),.y('d1), .out( pwr_str[0] ), .str("Cap J 0x") );
	hex_overlay    #(.LEN(2)) _pwr1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char)    , .x('d108),.y('d1), .out( pwr_str[1] ), .in( ecap[39-:8] ) );
	string_overlay #(.LEN(1)) _pwr2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d110),.y('d1), .out( pwr_str[2] ), .str(".") );
	hex_overlay    #(.LEN(5)) _pwr3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char)    , .x('d111),.y('d1), .out( pwr_str[3] ), .in( ecap[31-:20]) );

	string_overlay #(.LEN(8)) _pwr4 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d100),.y('d3), .out( pwr_str[4] ), .str("Out J 0x") );
	hex_overlay    #(.LEN(2)) _pwr5 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char)    , .x('d108),.y('d3), .out( pwr_str[5] ), .in( eout[39-:8] ) );
	string_overlay #(.LEN(1)) _pwr6 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d110),.y('d3), .out( pwr_str[6] ), .str(".") );
	hex_overlay    #(.LEN(5)) _pwr7 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char)    , .x('d111),.y('d3), .out( pwr_str[7] ), .in( eout[31-:20]) );
	
	
	
	// 12 bit resistance number is 6.5. so 
	// plotting as 8.4 with { 2`b00, in[10:1] } will give Ohms. A decimal point woudl be nice
	logic [4:0] res_str;
	string_overlay #(.LEN(8)) _res0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d100),.y('d5), .out( res_str[0] ), .str("Res $ 0x") );
	hex_overlay    #(.LEN(2)) _res1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char)    , .x('d108),.y('d5), .out( res_str[1] ), .in( { 2'b00, igniter_res[10:5] ^ 6'h3F } ) );
	string_overlay #(.LEN(1)) _res2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d110),.y('d5), .out( res_str[2] ), .str(".") );
	hex_overlay    #(.LEN(1)) _res3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char)    , .x('d111),.y('d5), .out( res_str[3] ), .in( { igniter_res[4:1] ^ 4'hF } ) );
	//string_overlay #(.LEN(11))_res4 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('d117),.y('d5), .out( res_str[4] ), .str("(3E.E=Open)") );

	
	// Port Names
	logic [3:0] in_str;
   //string_overlay #(.LEN(2)) _in0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h48),.y('h01), .out( in_str[0]), .str("A0") );
	//string_overlay #(.LEN(2)) _in1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h48),.y('h03), .out( in_str[1]), .str("A1") );
	//string_overlay #(.LEN(2)) _in2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h48),.y('h05), .out( in_str[2]), .str("B0") );
	//string_overlay #(.LEN(2)) _in3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .ascii_char(ascii_char), .x('h48),.y('h07), .out( in_str[3]), .str("B1") );
	
	// 12bit hex overlays(4)
	logic [3:0] hex_str;
	//hex_overlay #(.LEN(3)) _hex0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h4B),.y('h01), .out( hex_str[0]), .in( value_1 ) );
	//hex_overlay #(.LEN(3)) _hex1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h4B),.y('h03), .out( hex_str[1]), .in( value_2 ) );
	//hex_overlay #(.LEN(3)) _hex2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h4B),.y('h05), .out( hex_str[2]), .in( value_3 ) );
	//hex_overlay #(.LEN(3)) _hex3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .hex_char(hex_char), .x('h4B),.y('h07), .out( hex_str[3]), .in( value_4 ) );
					
	// dump binary	values	
	logic [3:0] bin_str;
	//bin_overlay #(.LEN(12)) _bin0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h4B), .y('h01), .out( bin_str[0] ), .in( value_1 ) );
	//bin_overlay #(.LEN(12)) _bin1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h4B), .y('h03), .out( bin_str[1] ), .in( value_2 ) );
	//bin_overlay #(.LEN(12)) _bin2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h4B), .y('h05), .out( bin_str[2] ), .in( value_3 ) );
	//bin_overlay #(.LEN(12)) _bin3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h4B), .y('h07), .out( bin_str[3] ), .in( value_4 ) );

	
	// Dump Diag bits
	logic [3:0] diag_str;
	//bin_overlay #(.LEN(1)) _diag0 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h46), .y('h01), .out( diag_str[0] ), .in( diag_reg[3] ) );
	//bin_overlay #(.LEN(1)) _diag1 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h46), .y('h03), .out( diag_str[1] ), .in( diag_reg[2] ) );
	//bin_overlay #(.LEN(1)) _diag2 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h46), .y('h05), .out( diag_str[2] ), .in( diag_reg[1] ) );
	//bin_overlay #(.LEN(1)) _diag3 (.clk(hdmi_clk), .reset(reset), .char_x(char_x), .char_y(char_y), .bin_char(bin_char), .x('h46), .y('h07), .out( diag_str[3] ), .in( diag_reg[0] ) );
	
	// Merge overlays
	logic overlay;
	assign overlay = (|diag_str) | 
	                 (|bin_str ) |
						  (|hex_str ) |
						  (|pwr_str ) |
						  (|in_str  ) |
						  ( text_ovl && text_color == 0 ) | // normal text
						  ( key_strg) |
						  (|res_str ) |
						  (|id_str  ) ;
	
	// video encoder
	//logic [7:0] hdmi_data;
	//video_encoder _encode
	//(
	//	.clk(  hdmi_clk  ),
	//	.clk5( hdmi_clk5 ),
	//	.reset( reset ),
	//	.blank( blank ),
	//	.hsync( hsync ),
	//	.vsync( vsync ),
	//	.red	( ( test_red   | {8{overlay}} | scope_red   ) ),
	//	.green( ( test_green | {8{overlay}} | scope_green ) ),
	//	.blue	( ( test_blue  | {8{overlay}} | scope_blue  ) ),
	//	.hdmi_data( hdmi_data )
	//);	
	
	//hdmi_out _hdmi_out ( // LDVS DDR outputs
	//	.outclock( hdmi_clk5 ),
	//	.din( hdmi_data ),
	//	.pad_out( {hdmi_d2, hdmi_d1, hdmi_d0, hdmi_ck} ), 
	//	.pad_out_b( )  // true differential, _b not req
	//);
	
	

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

	// Overlay Color
	logic [7:0] overlay_red, overlay_green, overlay_blue;
	
	assign { overlay_red, overlay_green, overlay_blue } =
			( overlay ) ? 24'hFFFFFF :
			( text_ovl && text_color == 4'h1 ) ? 24'hf00000 :
			( text_ovl && text_color == 4'h2 ) ? 24'hFFFFFF :
			( text_ovl && text_color == 4'h3 ) ? 24'hff0000 :			
			( text_ovl && text_color == 4'h4 ) ? 24'h00ff00 :
			( text_ovl && text_color == 4'h5 ) ? 24'h0000ff :
			( text_ovl && text_color == 4'h6 ) ? 24'hc0c0c0 :
			( text_ovl && text_color == 4'h7 ) ? 24'h0000c0 :
			( text_ovl && text_color == 4'h8 ) ? 24'h00c0c0 :
			( text_ovl && text_color == 4'h9 ) ? 24'h00c000 : 
			( text_ovl && text_color == 4'hA ) ? 24'hc0c000 : 
			( text_ovl                       ) ? 24'hf0f000 : 
															 24'h000000 ;

	// video encoder
	logic [7:0] hdmi2_data;
	logic [7:0] dvi_data;
	video_encoder _encode2
	(
		.clk  ( hdmi_clk  ),
		.clk5 ( hdmi_clk5 ),
		.reset( reset | charge ),  // battery limit during charging
		.blank( blank ),
		.hsync( hsync ),
		.vsync( vsync ),
		// HDMI encoding control
		.video_preamble( video_preamble ),
		.data_preamble ( data_preamble  ),
		.video_guard   ( video_guard    ),
		.data_guard    ( data_guard     ),
		.data_island   ( data_island    ),	
		// YUV mode input
		.yuv_mode		( blipvert ), // use YUV2 mode, cheap USb capture devices provice lossless YUV2 capture mode 
		// RBG Data
//		.red	( (blipvert) ? ((bv_vvalid_n) ? 8'h00 : (bv_vdata[16] ? 8'h08 : 8'h04) ) 
//		                   : ((( tiny ) ? tiny_red   : wave_scope_red   ) | overlay_red   )),
//		.green( (blipvert) ? ((bv_vvalid_n) ? 8'h00 :  bv_vdata[15:8] ) 
//		                   : ((( tiny ) ? tiny_green : wave_scope_green ) | overlay_green )),
//		.blue	( (blipvert) ? ((bv_vvalid_n) ? 8'h00 :  bv_vdata[7:0]  ) 
//		                   : ((( tiny ) ? tiny_blue  : wave_scope_blue  ) | overlay_blue  )),
		.red	( (blipvert) ? bv_vdata[7:0]  : ((( tiny ) ? tiny_red   : wave_scope_red   ) | overlay_red   ) ),
		.green( (blipvert) ? bv_vdata[15:8] : ((( tiny ) ? tiny_green : wave_scope_green ) | overlay_green ) ),
		.blue	( (blipvert) ? 8'h00          : ((( tiny ) ? tiny_blue  : wave_scope_blue  ) | overlay_blue  ) ),
		.hdmi_data( hdmi2_data ),
		.dvi_data( dvi_data ),
	);
		
	// HDMI 2 Output, DVI outputs
	hdmi_out _hdmi2_out ( // LDVS DDR outputs
		.outclock( hdmi_clk5 ),
		.din( dvi_data ),
		.pad_out( {hdmi2_d2, hdmi2_d1, hdmi2_d0, hdmi2_ck} ), 
		.pad_out_b( )  // true differential, _b not req
	);
	
	// HDMI 1 output, HDMI outputs, with YUV2 support
	hdmi_out _hdmi_out ( // LDVS DDR outputs
		.outclock( hdmi_clk5 ),
		.din( hdmi2_data ),
		.pad_out( {hdmi_d2, hdmi_d1, hdmi_d0, hdmi_ck} ), 
		.pad_out_b( )  // true differential, _b not req
	);

endmodule

// 1024 moving window debounce 80/20
// tick is about 1 per 480 cycles



			
module debounce(
	input clk,
	input reset,
	input in,
	output out,	// fixed pulse 15ms after 5ms pressure
	output long // after fire held for > 2/3 sec, until release
	);
	
	logic [25:0] count1; // total 1.3 sec
	logic [22:0] count0;
	logic [2:0] state;
	logic [2:0] meta;
	logic       inm;

	
	always @(posedge clk) { inm, meta } <= { meta, in };
	
	// State Machine	
	localparam S_IDLE 		= 0;
	localparam S_WAIT_PRESS	= 1;
	localparam S_WAIT_PULSE	= 2;
	localparam S_WAIT_LONG	= 3;
	localparam S_LONG			= 4;
	localparam S_WAIT_OFF	= 5;
	localparam S_WAIT_LOFF	= 6;
	
	always @(posedge clk) begin
		if( reset ) begin
			state <= S_IDLE;
		end else begin
			case( state )
				S_IDLE 		 :	state <= ( inm ) ? S_WAIT_PRESS : S_IDLE;
				S_WAIT_PRESS :	state <= (!inm ) ? S_IDLE       : (count1 == ( 5  * 48000 )) ? S_WAIT_PULSE : S_WAIT_PRESS;
				S_WAIT_PULSE :	state <=                          (count1 == ( 25 * 48000 )) ? S_WAIT_LONG  : S_WAIT_PULSE; 
				S_WAIT_LONG	 :	state <= (!inm ) ? S_WAIT_OFF   : (count1 >= 26'h20_00000  ) ? S_LONG       : S_WAIT_LONG;
				S_LONG		 :	state <= (!inm ) ? S_WAIT_LOFF  :  S_LONG;
				S_WAIT_OFF	 :	state <= ( inm ) ? S_WAIT_LONG  : (count0 == ( 100 * 48000)) ? S_IDLE       : S_WAIT_OFF;
				S_WAIT_LOFF	 :	state <= ( inm ) ? S_LONG       : (count0 == ( 100 * 48000)) ? S_IDLE       : S_WAIT_LOFF;
				default: state <= S_IDLE;
			endcase
		end
	end
	
	assign out = (state == S_WAIT_PULSE) ? 1'b1 : 1'b0;
	assign long = (state == S_LONG || state == S_WAIT_LOFF) ? 1'b1 : 1'b0;
	
	// Counters
	always @(posedge clk) begin
		if( reset ) begin
			count0 <= 0;
			count1 <= 0;
		end else begin
			count0 <= ( state == S_WAIT_OFF  || 
			            state == S_WAIT_LOFF ) ? (count0 + 1) : 0; // count when low waiting
			count1 <= ( state == S_IDLE      ) ? 0            : (count1 + 1); 
		end
	end

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

// BlipVert - From max headroom
// dump the entire memory as video pixels
// When enabled during active video line pels (!blank)
// writes address, end then burst reads 1kB to video each scanline

module blipvert (
	input clk,
	input reset,
	input enable,
	input [24:0] base, // starting block addr
	// Axi4 read Bus
	output logic [24:0] araddr,
	output logic [7:0]  arlen,
	output logic        arvalid,
	input  logic        arready,
	input  logic [17:0] rdata,
	input  logic        rvalid,
	// Video output data to fifo to hdmi live video
	output [16:0] vdata,
	output        vvalid
	);
	
	// State machine
	logic [1:0] state;
	localparam S_IDLE 	= 0;
	localparam S_ADDR 	= 1;
	localparam S_VALID   = 2;
	localparam S_WAIT		= 3;
	
	always @(posedge clk) begin
		if( reset ) begin
			state <= S_IDLE;
		end else begin
			case( state )
				S_IDLE : state <= ( enable ) ? S_ADDR : S_IDLE;
				S_ADDR : state <= ( enable ) ? S_VALID : S_IDLE;
				S_VALID: state <= ( !enable ) ? S_IDLE :
			                      ( arready && arvalid && addr[9:6] == 4'hF ) ? S_WAIT : S_VALID; 
				S_WAIT : state <= ( enable ) ? S_WAIT : S_IDLE;
			endcase
		end
	end
	assign arvalid = ( state == S_VALID ) ? 1'b1 : 1'b0;

	// Read Address
	logic [24:0] addr;
	logic [24:10] next_addr;
	
	assign next_addr[24:10] = addr[24:10] + 1;

	always @(posedge clk) begin
		if( reset ) begin
			addr <= 0;
		end else begin
			addr[5:0] <= 0;
			addr[9:6] <= ( state == S_ADDR ) ? 4'h0 :
			             ( state == S_VALID && arready && arvalid ) ? addr[9:6] + 4'h1 : addr[9:6];
			addr[24:10] <= ( state == S_ADDR ) ? next_addr[24:10] : addr[24:10];
		end
	end
	assign araddr[24:0] = addr[24:0];
	assign arlen[7:0] = 8'd32; 

	// Output
	always @(posedge clk) begin
		vvalid <= ( state == S_ADDR || ( enable && rvalid )) ? 1'b1 : 1'b0;
		vdata  <= ( state == S_ADDR ) ? { 2'b1, next_addr[24:10] == base[24:10], next_addr[24:10] } : // addr flag, start flag, addr 1k
		                                { 1'b0, rdata[16:9], rdata[7:0] }; // mem data
	end
	
endmodule