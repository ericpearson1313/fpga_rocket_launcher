`timescale 1ns / 1ps
// ForgeFPGA model rocket launcher
// Digital PWM, current controlled buck converter. capacitive discharge
// igniter pulse generator 
module forge_launcher
(
	// System
	input logic clk,
	input logic reset,

	// Front Panel I/O
	input  logic fire_button,
	output logic arm_led,
	output logic cont_led,
	output logic speaker,

	// High Voltage 
	output logic lt3420_charge,
	input  logic lt3420_done,
	output logic pwm,	
	output logic dump,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	//output logic		ad_sclk, handled in wrapper
	input  logic  [1:0] ad_sdata_a,
	input  logic  [1:0] ad_sdata_b,
	
	///////////////////
	// Emulation I/o //
	///////////////////
	
	// Debug Controls
	input 	logic [2:0] iset, // dip switch active low
	input	logic [4:0] key,  // keypad 
	
	// monitor outputs for Display
	output logic [11:0] 	ad_a0, 
	output logic [11:0] 	ad_a1, 
	output logic [11:0] 	ad_b0, 
	output logic [11:0] 	ad_b1,
	output logic 			ad_strobe,
	output logic [11:0] 	iest,
	output logic 			burn = 0,
	output logic [11:0]	igniter_res,	
	
	// Display and Logging control outputs
	output logic scroll_halt = 0,
	output logic charge = 1,	// 1=AUTORUN
	output logic fire_done = 0,
	output logic fire_button_debounce,
	output logic cap_halt = 0,
	output logic long_fire
);

	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
	parameter COIL_IND_UH = 390;


// Free running counter
logic [25:0] count;
always_ff @(posedge clk) 
	count <= count + 1;

//////////////////////////////////////////////
// fire button 10ms debounce 
// signal to get 1.3 sec of pwm current control
// signal One shot capture mode on 1st rising pwm edge 1.3 sec
// signal to set discharge at 1.3sec
// signal to stop tiny scroll window at 4.3 sec
//////////////////////////////////////////////

logic [27:0] fire_count = 0; 
logic fire_flag = 0;

forge_debounce #( CLOCK_FREQ_MHZ ) _firedb ( .clk( clk ), .reset( reset ), .in( fire_button ), .out( fire_button_debounce ), .long( long_fire ));

parameter PWM_START     = 1; // Enable PWM current control 
parameter PWM_END			= (CLOCK_FREQ_MHZ*4/3) * 1000 * 1000; // Total time 1.333 sec
parameter SCROLL_HALT	= (CLOCK_FREQ_MHZ*13/3) * 1000 * 1000; // Total time 4.333 sec
parameter CAP_HALT		= PWM_START + 1000 * CLOCK_FREQ_MHZ/3; // stop capture before re-trigger or wrap

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
initial charge = 1;
logic continuity = 0; // test cont flag
always @( posedge clk ) begin
	if( reset ) begin
		charge <= !iset[2]; //Latch on reset
		continuity <= 0;
	end else begin
		if( lt3420_done && charge ) begin // switch to continuity
			charge <= 0;
			continuity <= 1;
		end else if( continuity && fire_flag ) begin
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
		if( CLOCK_FREQ_MHZ == 24 ) begin
			{spk_en, tone_cnt}<= ( key == 5'h11 || fire_button_debounce ) ? { 1'b1, 16'h1665 } :
										//( key == 5'h12 ) ? { 1'b1, 16'h13f3 } :
										( key == 5'h13 ) ? { 1'b1, 16'h11c6 } :
										//( key == 5'h14 ) ? { 1'b1, 16'h10C7 } :
										( key == 5'h15 ) ? { 1'b1, 16'h0EF2} :
										//( key == 5'h16 ) ? { 1'b1, 16'h0d51 } :
										//( key == 5'h17 ) ? { 1'b1, 16'h0bdd } :
										( /*key == 5'h18 ||*/ ( (cont_tone && !iset[0]) || first_tone ) ) ? { 1'b1, 16'h0b32 } : 0; // sw0 mutes tone
		end else begin // CLK_FREQ_MHZ == 48
			{spk_en, tone_cnt}<= ( key == 5'h11 || fire_button_debounce ) ? { 1'b1, 16'h2CCA } :
										//( key == 5'h12 ) ? { 1'b1, 16'h27E7 } :
										( key == 5'h13 ) ? { 1'b1, 16'h238D } :
										//( key == 5'h14 ) ? { 1'b1, 16'h218E } :
										( key == 5'h15 ) ? { 1'b1, 16'h1DE5 } :
										//( key == 5'h16 ) ? { 1'b1, 16'h1AA2 } :
										//( key == 5'h17 ) ? { 1'b1, 16'h17BA } :
										( /*key == 5'h18 ||*/ ( (cont_tone && !iset[0]) || first_tone ) ) ? { 1'b1, 16'h1665 } : 0; // sw0 mutes tone
		end
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
 
logic current_seen = 0;
logic [11:0] ad_b1_del = 12'h7ff;
logic signed [12:0] dv; // delta voltage

assign dv[12:0] = { ad_b1[11], ad_b1[11:0] ^ 12'h7ff } - { ad_b1_del[11], ad_b1_del[11:0] ^ 12'h7ff };
initial ad_b1_del <= 12'h7ff;
logic signed [12:0] max_dvdt = 24 * (16 * 10000) / (ADC_VOLTS_PER_DN * 10000 * CLOCK_FREQ_MHZ); // (24 v/usec limit * 16 cyc/sample)/(.2005 v/dn * 48 Mhz)
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
				   ( fire_flag && ( dv > max_dvdt ))	// dv > +24 V/us
					) ? 1'b1 : burn; 
		ad_b1_del <= ad_b1; // ad_b1 only changes on sample x16, but is fine for our detection use
		//burn <= ( fire_flag && ( dv > 13'sd50 ) ) ? 1'b1 : burn; // rise rate > 10V/sample == 30 V/usec
	end
end

////////////////////////////////////////////
// PWM Current limited pulse generator
////////////////////////////////////////////
logic 			pwm_pulse = 0;
logic [15:0] 	pulse_time = 0;
logic [9:0] 	pulse_count = 0;
logic				ramp_flag = 0;

logic [11:0] 	thresh_hi, thresh_lo;

localparam THRESH_TIME = ( CLOCK_FREQ_MHZ == 24 ) ? 28'h00_40000 : 28'h00_80000;  // time to change setpoint
always @(posedge clk) thresh_hi <= (fire_flag && fire_count >= THRESH_TIME ) ? ( 205 * 4 + 20 ) : ( 205 * 2 + 20 ); // setpoint 2Amp start, +1/6 sec in 4Amp
always @(posedge clk) thresh_lo <= (fire_flag && fire_count >= THRESH_TIME ) ? ( 205 * 4 - 20 ) : ( 205 * 2 - 20 );

always @(posedge clk) begin
	if( reset ) begin
		pwm_pulse <= 0;
		pulse_time <= 0;
		pulse_count <= 0;
		ramp_flag <= 0;
	end else begin
		if( pwm_pulse ) begin // turn off pulse if time or current level exceeded
			if( pulse_time < (CLOCK_FREQ_MHZ*2/3) ) begin // min pulse width 750usec
				pwm_pulse <= pwm_pulse;
				pulse_count <= pulse_count;
				pulse_time <= pulse_time + 1; // inc count	
				ramp_flag <= ramp_flag;
			end else if(( burn )																	// burnthrough
			         || ( pulse_time >= (CLOCK_FREQ_MHZ  * 16))    					// 16 usec max on time
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
			if( pulse_time < (CLOCK_FREQ_MHZ * 4) ) begin // min pulse off time is 4 Usec
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
			pulse_count <= 3; // two pulses
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
forge_adc_module_4ch  _adc (
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
forge_model_coil #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) _model (
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

logic res_pwm;
forge_igniter_continuity #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ ) _res_cont (
	.clk( clk ),
	.reset( reset ),
	// Votlage and Current Inputs
	.valid_in( ad_strobe ),
	.v_in( ad_b1 ), // ADC Vout
	.i_in( ad_a0 ), // ADC Iout
	// PWM output and enable input
	.pwm( res_pwm ),
	.enable( key == 5'h19 || continuity ),
	// Tone and LED output
	.tone( cont_tone ),
	.first_tone( first_tone ),
	.led( cont_led )
);

assign pwm = pwm_pulse | res_pwm;

// Arm is based on vcap with 300v on thresh and 50v off thresh
// clip inputs to +ve
logic [10:0] vcap;
assign vcap = ( ad_a1[11] || ad_a1[10:4] == 7'h7F ) ? 11'b0 : ( ad_a1[10:0] ^ 11'h7ff );

logic cap_charged = 0;
always @( posedge clk ) begin
	if( reset ) begin
		cap_charged <= 0;
	end else begin
		cap_charged <= ( ad_strobe && vcap > (( 300 * 10000 ) / 2005 ) ) ? 1'b1 :
		               ( ad_strobe && vcap < (( 50  * 10000 ) / 2005 ) ) ? 1'b0 : cap_charged;
	end
end

assign arm_led = cap_charged | ( charge && ((CLOCK_FREQ_MHZ==24)?(count[23:20]==0):(count[24:21]==0)) );

endmodule

			
module forge_debounce(
	input clk,
	input reset,
	input in,
	output out,	// fixed pulse 15ms after 5ms pressure
	output long // after fire held for > 2/3 sec, until release
	);

	parameter CLOCK_FREQ_MHZ = 48;	
	localparam CYC_PER_MS = CLOCK_FREQ_MHZ * 1000; // 1 Ms count time
	localparam CYC_LONG   = ( CLOCK_FREQ_MHZ * 2 / 3 ) * 'h100000;
	
	logic [25:0] count1 = 0; // total 1.3 sec
	logic [22:0] count0 = 0;
	logic [2:0] meta;
	logic       inm;

	
	always @(posedge clk) { inm, meta } <= { meta, in };
	
	// State Machine	
	localparam S_IDLE 		= 0;
	localparam S_WAIT_PRESS	= 1;
	localparam S_WAIT_PULSE	= 2;
	localparam S_WAIT_LONG	= 3;
	localparam S_LONG		= 4;
	localparam S_WAIT_OFF	= 5;
	localparam S_WAIT_LOFF	= 6;
	
	logic [2:0] state = S_IDLE;
	always @(posedge clk) begin
		if( reset ) begin
			state <= S_IDLE;
		end else begin
			case( state )
				S_IDLE 		 :	state <= ( inm ) ? S_WAIT_PRESS : S_IDLE;
				S_WAIT_PRESS :	state <= (!inm ) ? S_IDLE       : (count1 == ( 5  * CYC_PER_MS )) ? S_WAIT_PULSE : S_WAIT_PRESS;	// 5 msec debounce on
				S_WAIT_PULSE :	state <=                          (count1 == ( 25 * CYC_PER_MS )) ? S_WAIT_LONG  : S_WAIT_PULSE; 	// 25 msec pusle
				S_WAIT_LONG	 :	state <= (!inm ) ? S_WAIT_OFF   : (count1 >=          CYC_LONG  ) ? S_LONG       : S_WAIT_LONG;			// 0.66 sec long
				S_LONG		 :	state <= (!inm ) ? S_WAIT_LOFF  :  S_LONG;
				S_WAIT_OFF	 :	state <= ( inm ) ? S_WAIT_LONG  : (count0 == ( 100 * CYC_PER_MS)) ? S_IDLE       : S_WAIT_OFF;		// 100 mses debounce off
				S_WAIT_LOFF	 :	state <= ( inm ) ? S_LONG       : (count0 == ( 100 * CYC_PER_MS)) ? S_IDLE       : S_WAIT_LOFF;
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
	
	
module forge_adc_module_4ch 
(
	// Input clock, reset
	input logic clk,
	input logic reset,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	input  logic  [1:0] ad_sdata_a,
	input  logic  [1:0] ad_sdata_b,
	
	// ADC monitor outputs
	output [11:0] ad_a0,
	output [11:0] ad_a1,
	output [11:0] ad_b0,
	output [11:0] ad_b1,
	output ad_strobe
);

// ADC sample pulse 
// RUn ADCs in-continuous mode.
// The fall of the CS signal is actually the moment of sampling, and MSB becomes valid
parameter ADC_CYCLES = 5'd16; // 16 for 48Mhz, 15 for 45Mhz to give a 3Mhz sample rate. 
										// CS is active low for 14 cycles to give a 12 bit output
reg [4:0] sample_div = ADC_CYCLES - 5'd1;
initial sample_div = ADC_CYCLES - 5'd1;
always @(posedge clk) begin
	if( reset ) begin
		sample_div <= ADC_CYCLES - 5'd1;
	end else begin
		sample_div <= (sample_div == 0) ? (ADC_CYCLES - 5'd1) : sample_div - 5'd1;
	end
end
assign ad_cs = ( /*state_q == S_FIRE &&*/ sample_div == 5'd0 ) ? 1'b1 : 1'b0;


// CS pipeline to trigger everything
logic [20:0] cs_delay = 0;
always @(posedge clk) begin
	if( reset ) begin
		cs_delay[20:0]     <= 21'd0;
   end else begin
		// shift chain for the chip select
		cs_delay[20:0]  <= { cs_delay[19:0], ad_cs };		
	end
end

// DATA Input Receiver

logic [11:0] ad_load_a0 = 0, ad_load_a1 = 0, ad_load_b0 = 0, ad_load_b1 = 0;
logic [11:0] ad_hold_a0 = 0, ad_hold_a1 = 0, ad_hold_b0 = 0, ad_hold_b1 = 0;
logic [11:0] load;

parameter LOAD_SEL = 1;   // select first load delay, load reg input (ie 1 cycle early).
parameter HOLD_SEL = 14;  // select output hold delay bit
parameter VALID_SEL = 15;   // the cycle the adc hold registers are updatead

always @(posedge clk) begin
	if( reset ) begin
		ad_load_a0[11:0] <= 12'd0;
		ad_load_a1[11:0] <= 12'd0;
		ad_load_b0[11:0] <= 12'd0;
		ad_load_b1[11:0] <= 12'd0;
		ad_hold_a0[11:0] <= 12'd0;
		ad_hold_a1[11:0] <= 12'd0;
		ad_hold_b0[11:0] <= 12'd0;
		ad_hold_b1[11:0] <= 12'd0;
   end else begin
		// Load Pulse Chain
		load[11:0] <= { cs_delay[LOAD_SEL], load[11:1] };
		// low power reg load with bit 
		for( int ii = 0; ii < 12; ii++ ) begin
			ad_load_a0[ii] <= ( load[ii] ) ? ad_sdata_a[0] : ad_load_a0[ii];
			ad_load_a1[ii] <= ( load[ii] ) ? ad_sdata_a[1] : ad_load_a1[ii];
			ad_load_b0[ii] <= ( load[ii] ) ? ad_sdata_b[0] : ad_load_b0[ii];
			ad_load_b1[ii] <= ( load[ii] ) ? ad_sdata_b[1] : ad_load_b1[ii];
		end
		// Load hold reg 
		begin
			ad_hold_a0 <= (cs_delay[HOLD_SEL]) ? ad_load_a0 : ad_hold_a0;
			ad_hold_a1 <= (cs_delay[HOLD_SEL]) ? ad_load_a1 : ad_hold_a1;
			ad_hold_b0 <= (cs_delay[HOLD_SEL]) ? ad_load_b0 : ad_hold_b0;
			ad_hold_b1 <= (cs_delay[HOLD_SEL]) ? ad_load_b1 : ad_hold_b1;
		end
	end
end

logic adc_valid;
assign adc_valid = cs_delay[VALID_SEL];

// Monitor outputs with bias offsets
assign ad_a0 = ad_hold_a0 + 12'h5;
assign ad_a1 = ad_hold_a1 + 12'h5;
assign ad_b0 = ad_hold_b0 + 12'h5;
assign ad_b1 = ad_hold_b1 + 12'h6;
assign ad_strobe = adc_valid; // valid pulse aligned with new data.

endmodule



// This is a digital model of the current rise in the output inductor.
// This model runs at 48 Mhz (vs 3 Mhz sample rate) and give
// 16x timing precision and lower latency.
// Inputs are the PWM signal and slowely varying capacitor and output voltages. 
// The measured iout is also provided to intialize the model on PWM rising edge
// The model is ideal and optimisitic and will over-perform actual inductor current.
module forge_model_coil
(
	// Input clock, reset
	input logic clk,
	input logic reset,	
	// ADC voltage inputs (sample and held )
	input logic [11:0] vcap, // ADC native signed format. +-401V gives -+2000DN
	input logic [11:0] vout, // -.2005V/DN, about 5 digital number steps per volt
	// Measured current
	input logic [11:0] iout, // used to re-initialize the model
	// PWM signal 
	input logic pwm,
	// Esimated Coil current 
	output [11:0] iest_coil // +-10A = -+2050 + 2048, so 205DN/A 
);

// ADC Scale parameters
parameter ADC_VOLTS_PER_DN = 0.2005;
parameter ADC_DN_PER_AMP = 205;
// Physical parameters
parameter CLOCK_FREQ_MHZ = 48;
parameter COIL_IND_UH = 390;

// Current Model assignments and accumulator
// Multiply by 1/Lf
logic [23:0] iest_cur, iest_hold, iest_next, i_acc = 0;

/////////////////////////
// Coil Current Model
/////////////////////////

// Pre-process adc cap and output voltages (format, clip to zero with deadzone
logic [11:0] vcap_corr;
logic [11:0] vout_corr;
assign vcap_corr[11:0] = ( vcap[11:0] ^ 12'h7FF ); // signed 
assign vout_corr[11:0] = ( vout[11:0] ^ 12'h7FF ); // signed

// Calc deltaV across the coil when PWM On

logic [12:0] deltav;
always_ff @(posedge clk) deltav[12:0] <= { vcap_corr[11], vcap_corr[11:0] } - { vout_corr[11], vout_corr[11:0] };

// Use table lookup on &msbs of deltaV to calc deltai
logic [15:0] deltai_rom[63:0];// rom deltaI units in (4.12)
always_comb begin
	for( int ii = 0; ii < 64; ii++ )
		deltai_rom[ii] = ( (ii * 32 + 16) * 4096 * ADC_VOLTS_PER_DN * ADC_DN_PER_AMP ) / ( CLOCK_FREQ_MHZ * COIL_IND_UH );
end

logic [15:0] deltai;
always_ff @(posedge clk) deltai <= deltai_rom[(deltav[12])?0:deltav[10-:6]]; // 6 msb bits 

// Iest current is signed 12.12 in ADC current DN scale
always_ff @(posedge clk)
	iest_next[23:0] <= i_acc[23:0] + { 8'h00, deltai };
	
// current accumulator
logic pwm_del;
always @(posedge clk) pwm_del <= pwm;
always @(posedge clk) begin
	if( reset ) begin
		i_acc[23:0] <= 36'b0;
	end else if( !pwm ) begin // load rea value when pwm is low.
		i_acc[23:0] <= { ( iout[11] ) ? 12'h0 : ( iout[11:0] ^ 12'h7ff ), 12'h000 };
	end else begin // Accumulate during PWM for rise
		i_acc[23:0] <= iest_next; // 12 fractional bits
	end
end

// Ouput estimate is in adc units 
assign iest_coil[11:0] = i_acc[23-:12] ^ 12'h7ff;

endmodule // model_coil
	
// Continuity Module
// Save gates over full resistance calculation, loose the 'short' detect capability.
// Enable input assertion, creates a PWM pulse (2us), and 64K hold-off on retrigger
// records max output current and voltage
// if Imax < 0.5amps --> Open, else
// else if Vmax > 30 volts resistance is high else good 
// Beep codes and continuity led are generated as outputs
module forge_igniter_continuity
(
	// System
	input logic clk,
	input logic reset,
	
	// ADC Inputs (output I,V)
	input logic valid_in,
	input logic [11:0] v_in, 
	input logic [11:0] i_in,	
	
	// PWM Output
	output pwm,

	// input Enable
	input enable,
	
	// Outputs
	output tone,
	output first_tone,
	output logic led = 0
);
	
	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;
	
	
	// Triggering with 0.6 Sec holdoff
	logic [24:0] holdoff = 0;
	always @(posedge clk) begin
		if( reset ) begin
			holdoff <= 0;
		end else begin
			if( !enable ) begin
				holdoff <= 0;
			end else if( enable && ( holdoff == 0 ) ) begin // start
				holdoff <= 1;
			end else if( holdoff != 0 ) begin // holdoff delay until wrap
				holdoff <= holdoff + 1;
			end else begin
				holdoff <= 0;
			end
		end
	end
	
	// PWM output, 2usec
	assign pwm = ( ( holdoff != 0 ) && ( holdoff < ( CLOCK_FREQ_MHZ * 2 ))) ? 1'b1 : 1'b0; // 2 uSec continuity pulse
	
	// foramt and Clip inputs
	logic [10:0] current;
	logic [10:0] voltage;
	assign current = ( i_in[11] | i_in[10:0] == 11'h7FF ) ? 11'h001 : ( i_in[10:0] ^ 11'h7FF );
	assign voltage = ( v_in[11] ) ? 11'h000 : ( v_in[10:0] ^ 11'h7ff );	
	
	localparam START_TIME = ( CLOCK_FREQ_MHZ == 24 ) ? 128 : 256;
	localparam END_TIME = ( CLOCK_FREQ_MHZ == 24 ) ? 2048 : 4096;
	
	// Max IV accumulate
	logic [10:0] imax = 0, vmax = 0;
	always @(posedge clk) begin
		if( reset ) begin
			imax <= 0;
			vmax <= 0;
		end else begin 
			if( holdoff == 0 ) begin // Idle, just hold values, zero acc
				imax <= 0;
				vmax <= 0;
			end else if( holdoff > START_TIME && holdoff < END_TIME && valid_in ) begin 
			   // accumulate valid samples
			    imax <= ( current > imax ) ? current : imax;
			    vmax <= ( voltage > vmax ) ? voltage : vmax;
			end else begin
				imax <= imax;
				vmax <= vmax;
			end
		end
	end
	
	// Set LED if between 1 and 16 ohms
	always @(posedge clk) begin
		if( reset ) begin
			led <= 0;
		end else begin // if we see 300mA there *IS* a connection
			led <= (enable == 0 ) ? 1'b0 : ( holdoff == END_TIME + 1 ) ? (( imax > 64 ) ? 1'b1 : 1'b0 ) : led;
		end
	end
	
	// Tones 
	// Open, imax 1 < 64(300ma) - 3 beep
	// vmax > 128 (25v) high resistance - 2 beeps
	// else 1 beeps 
	
	logic [3:0] beep_time;
	assign beep_time = ( CLOCK_FREQ_MHZ == 24 ) ? holdoff[23-:4] : holdoff[24-:4];
	assign tone = 	( beep_time == 1 ) ? 1'b1 : // always a single beep
						( beep_time == 3 && ( imax < 12'h040 || vmax > 12'h080 ) ) ? 1'b1 : // two beeps if open or high
						( beep_time == 5 && ( imax < 12'h040 )) ? 1'b1 : 1'b0; // three beeps if open

	logic first = 1;	
	initial first = 1;
	always @(posedge clk) begin
		if( reset ) begin
			first <= 1;
		end else begin
			first <= ( beep_time == 8 ) ? 1'b0 : first;
		end
	end
			
	assign first_tone = first & tone;
	
endmodule // forge_igniter_continuity