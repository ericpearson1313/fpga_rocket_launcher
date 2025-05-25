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
	input  logic arm_button,
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
	parameter CLOCK_FREQ_MHZ = 48;
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

forge_debounce _firedb ( .clk( clk ), .reset( reset ), .in( fire_button ), .out( fire_button_debounce ), .long( long_fire ));

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
 
logic current_seen = 0;
logic [11:0] ad_b1_del = 12'h7ff;
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
logic 			pwm_pulse = 0;
logic [15:0] 	pulse_time = 0;
logic [9:0] 	pulse_count = 0;
logic				ramp_flag = 0;

logic [11:0] 	thresh_hi, thresh_lo;

always @(posedge clk) thresh_hi <= (fire_flag && fire_count >= 28'h00_80000 ) ? ( 205 * 4 + 20 ) : ( 205 * 2 + 20 ); // setpoint 2Amp start, +1/6 sec in 4Amp
always @(posedge clk) thresh_lo <= (fire_flag && fire_count >= 28'h00_80000 ) ? ( 205 * 4 - 20 ) : ( 205 * 2 - 20 );

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

logic res_val;
logic [11:0] res_calc;
forge_ohm_div _resistance (
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
forge_igniter_resistance #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP ) _res_measurement (
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

assign arm_led = cap_charged | ( charge && count[24:21] == 0 );

endmodule

			
module forge_debounce(
	input clk,
	input reset,
	input in,
	output out,	// fixed pulse 15ms after 5ms pressure
	output long // after fire held for > 2/3 sec, until release
	);
	
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
assign vcap_corr[11:0] = ( vcap > 12'h7F8 ) ? 8 : ( vcap[11:0] ^ 12'h7FF ); // clip to >= 8, else model wanders
assign vout_corr[11:0] = ( vout[11] ) ? 0 : ( vout[11:0] ^ 12'h7FF ); // clip to zero if -ve

// Calc deltaV across the coil when PWM On
logic [6:0] deltav; // always possitive 
always_ff @( posedge clk ) deltav <= vcap_corr[10:4] - vout_corr[10:4]; // coil drive voltage

// Use table lookup on &msbs of deltaV to calc deltai
logic [15:0] deltai_rom[63:0];// rom deltaI units in (4.12)
always_comb begin
	for( int ii = 0; ii < 64; ii++ )
		deltai_rom[ii] = ( ii * 4096 * 32 * ADC_VOLTS_PER_DN * ADC_DN_PER_AMP ) / ( CLOCK_FREQ_MHZ * COIL_IND_UH );
end

logic [15:0] deltai;
always_ff @(posedge clk) deltai <= deltai_rom[deltav[10-:5]];

// Iest current is signed 12.12 in ADC current DN scale
always_ff @(posedge clk)
	iest_next[23:0] <= i_acc[23:0] + { 8'h00, deltai };
	
// current accumulator
logic pwm_del;
always @(posedge clk) pwm_del <= pwm;
always @(posedge clk) begin
	if( reset ) begin
		i_acc[23:0] <= 36'b0;
	end else if( pwm & ~pwm_del ) begin // load read value on pwm rise.
		i_acc[23:0] <= { ( iout[11] ) ? 12'h0 : ( iout[11:0] ^ 12'h7ff ), 24'h00_0000 };
	end else if ( pwm ) begin // Accumulate during PWM for rise
		i_acc[23:0] <= iest_next; // 12 fractional bits
	end else begin
		i_acc[23:0] <= i_acc[23:0];
	end
end

// Ouput estimate is in adc units 
assign iest_coil[11:0] = i_acc[23-:12] ^ 12'h7ff;

endmodule // model_coil


// Resitance Calc Module
// Enable input assertion, creates a PWM pulse (2us), and 64K hold-off on retrigger
// waits for a valid resistance calc (64 cycles), and then accumulates for total 128 cycles
// At each power of two an output resistance is provided. Output is latched.
// Beep codes and continuity are generated as outputs
module forge_igniter_resistance
(
	// System
	input logic clk,
	input logic reset,
	
	// Raw resistance
	input valid_in,
	input [11:0] r_in, // adc format, +ve only

	// PWM Output
	output pwm,

	// input Enable
	input enable,
	
	// Outputs
	output tone,
	output first_tone,
	output logic led = 0,
	output energy, // high when power accumulation should occur
	
	// Resistance Output
	output logic valid_out = 0,
	output logic [11:0] r_out = 0 // adc format, +ve only
);
	
	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	
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
	assign pwm = ( ( holdoff != 0 ) && ( holdoff < ( 48 * 2 ))) ? 1'b1 : 1'b0;
	
	// Accumulate and average
	logic [17:0] acc = 0; // max 128 samples of 11 bits
	logic [7:0] cnt = 0;
	always @(posedge clk) begin
		if( reset ) begin
			acc <= 0;
			cnt <= 0;
			r_out <= 0;
			valid_out <= 0;
		end else begin 
			if( holdoff == 0 ) begin // Idle, just hold values, zero acc
				cnt <= 0;
				acc <= 0;
				valid_out <= valid_out;
				r_out <= r_out;
			end else	if( holdoff > 256 && holdoff < 4096 && valid_in ) begin 
			   // accumulate valid samples
				cnt <= ( cnt == 8'hff ) ? 8'hff : cnt + 1;
				acc <= acc + { 7'h00, r_in[10:0] ^ 11'h7ff };
				valid_out <= 1;
				r_out <= ( cnt == (8'h04)) ? { 1'b0, acc[12-:11] ^ 11'h7ff }  :
							( cnt == (8'h08)) ? { 1'b0, acc[13-:11] ^ 11'h7ff }  :
							( cnt == (8'h10)) ? { 1'b0, acc[14-:11] ^ 11'h7ff }  :
							( cnt == (8'h20)) ? { 1'b0, acc[15-:11] ^ 11'h7ff }  :
							( cnt == (8'h40)) ? { 1'b0, acc[16-:11] ^ 11'h7ff }  :
							( cnt == (8'h80)) ? { 1'b0, acc[17-:11] ^ 11'h7ff }  : r_out;

			end else if( holdoff >= 4096 && cnt <= 3 ) begin // no resistance readings, so open circuit OR zero cap voltage
				cnt <= 0;
				acc <= 0;
				valid_out <= 1;
				r_out <= 12'h7DC ^ 12'h7ff;	// 3E.E ohms is code for "no valid reading / open circuit"		
			end else begin
				cnt <= cnt;
				acc <= acc;
				valid_out <= valid_out;
				r_out <= r_out;
			end
		end
	end
	
	// Set LED if between 1 and 16 ohms
	always @(posedge clk) begin
		if( reset ) begin
			led <= 0;
		end else begin // if 1 to 16 ohms show continuity (r_out in 6.5 format)
			led <= (enable == 0 ) ? 1'b0 : ( holdoff == 4097 ) ? ((( r_out ^ 12'h7ff ) >= 12'h020 &&  ( r_out ^ 12'h7ff ) < 12'h200 ) ? 1'b1 : 1'b0 ) : led;
		end
	end
	
	// Tones 
	// < 1 ohm - 4 beeps
	// 1 to 8 ohms - 1 beep
	// 0x3ee - 3 beeps
	// > 8 ohms - 2 beeps 
	
	assign tone = ( holdoff[24-:4] == 1 ) ? 1'b1 : // always a single beep
					  ( holdoff[24-:4] == 3 && !(( r_out ^ 12'h7ff ) > 12'h020 &&  ( r_out ^ 12'h7ff ) < 12'h100 )) ? 1'b1 : // two beeps if not in 1 to 8 ohm range
					  ( holdoff[24-:4] == 5 && ( ( r_out ^ 12'h7ff ) == 12'h7DC || ( r_out ^ 12'h7ff ) < 12'h020 )) ? 1'b1 : // three beeps if open or shorted
					  ( holdoff[24-:4] == 7 && ( ( r_out ^ 12'h7ff ) < 12'h020 )) ? 1'b1 :  1'b0; // four beeps if shorted
	logic first = 1;				  
	always @(posedge clk) begin
		if( reset ) begin
			first <= 1;
		end else begin
			first <= ( holdoff[24-:4] == 8 ) ? 1'b0 : first;
		end
	end
			
	assign first_tone = first & tone;
		
	// signal energy acculation
	
	assign energy = ( holdoff != 0 && holdoff < 4096 ) ? 1'b1 : 1'b0;
		
endmodule


// Output is calculated igniter resistance
// R = E / I ( done in native ADC units, convert thresholds)
// Inputs need conversion from ADC format
// Hardcoded for launch controller adc scale
// divider runs at 2 bits/cycle

module forge_ohm_div
(
	// System
	input logic clk,
	input logic reset,
	// ADC Inputs
	input logic valid_in,
	input logic [11:0] v_in,
	input logic [11:0] i_in,
	// Resistance Output
	output logic valid_out,
	output logic [11:0] r_out
);

logic [13:0] denom0 = 0, denom1 = 0, denom2 = 0, denom3 = 0;
logic [10:0] current; // in ADC units
logic [13:0] remd0, remd1, remd2, remd3 ; // remainder per q
logic [13:0] rem;
logic [38:0] numer = 0;

// fixed delay pipeline 16
// 1 cycle to load, 15 cycles of processing
	logic [15:0] del_valid = 0;
	always @(posedge clk) begin
		if( reset ) begin
			del_valid <= 0;
		end else begin
			del_valid  <= { del_valid[14:0], valid_in };
		end
	end

// I (current Input)
assign current[10:0] = ( i_in[11] | i_in[10:0] == 11'h7FF ) ? 11'h001 : ( i_in[10:0] ^ 11'h7FF );
always @(posedge clk) begin
	if( reset ) begin
		denom0 <= 0;
		denom1 <= 0;
		denom2 <= 0;
		denom3 <= 0;
	end else begin
		if( valid_in ) begin
		    denom0[13:0] <= 0;
			denom1[13:0] <= { 3'b000, current[10:0] };
			denom2[13:0] <= { 3'b000, current[10:0] }        + { 3'b000, current[10:0] };
			denom3[13:0] <= { 2'b00 , current[10:0] , 1'b0 } + { 3'b000, current[10:0] };				
		end else begin
			denom0 <= denom0;
			denom1 <= denom1;
			denom2 <= denom2;
			denom3 <= denom3;
		end
	end
end
	
// Voltage Input
// clip -ve to zero and format for input
logic [10:0] voltage; // in adc units
assign voltage = ( v_in[11] ) ? 11'h000 : ( v_in[10:0] ^ 11'h7ff );
logic [26:0] vscale; // scaled to normalize units << 10 precision
assign vscale[26:0] = { 1'b0, voltage[10:0], 15'h0000 };  // approx with 'h8000

// Divide steps and remainder
assign remd0[13:0] = numer[38-:14] - denom0[13:0]; // dummy
assign remd1[13:0] = numer[38-:14] - denom1[13:0];
assign remd2[13:0] = numer[38-:14] - denom2[13:0];
assign remd3[13:0] = numer[38-:14] - denom3[13:0];
assign rem[13:0] = ( !remd3[13] ) ? remd3 :
                   ( !remd2[13] ) ? remd2 :
				   ( !remd1[13] ) ? remd1 : remd0 ;

// Numerator shift, and accumulate
logic [29:0] quotient = 0;
always @( posedge clk ) begin
	if( reset ) begin
		numer <= 0;
		quotient <= 0;		
	end else begin
		if( valid_in ) begin
			numer[26:0] <= vscale[26:0];
			numer[38:27] <= 14'h0000;
			quotient <= 0;
		end else begin
			quotient[29:2] <= quotient[27:0];
			quotient[1:0] <= ( !remd3[13] ) ? 2'b11 :
			                 ( !remd2[13] ) ? 2'b10 :
			                 ( !remd1[13] ) ? 2'b01 : 2'b00 ;
			numer[1:0]   <= 2'b00;
			numer[26:2]  <= numer[24:0];
			numer[38:27] <= rem[11:0]; // assert rem[13:12] == 2'b00
		end
	end
end

// scale and hold resistance out.
// quotient is 17.13 format in ohms
// Clip to zero (7FF) until >150mA amp before measurement is meaningful
// Output is clipped to 6.5 and put into adc format
// TODO: Make sure R = 1..64 ohms fits in the output range

always @(posedge clk) begin
	valid_out   <= ( del_valid[15] && denom1 > 32 ) ? 1'b1 : 1'b0;
	r_out[11:0] <= ( del_valid[15] && denom1 > 32 ) ? { 1'b0, (|quotient[29:19])?11'h000 : (quotient[18-:11] ^ 11'h7FF) } :
                  ( del_valid[15] ) ? 12'h7FF : r_out;	
end

endmodule
	