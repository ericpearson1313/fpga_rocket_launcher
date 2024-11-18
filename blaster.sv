`timescale 1ns / 1ps
module blaster

#(
	// Parameter Declarations
	parameter UNIQ_ID = 32'h0000_0000
)

(
	// Input Buttons
	input  logic arm_button,
	input  logic fire_button,

	// Output LED/SPK
	output logic arm_led,
	output logic cont_led,
	output logic speaker,
	
	// Charger
	input  logic lt3420_done,
	output logic lt3420_charge,

	// Voltage Controls
	output logic pwm,
	output logic dump,

	// Continuity feedback
	input  logic cont,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	input  logic  [1:0] ad_sdata_a,
	input  logic  [1:0] ad_sdata_b,
	
	// ADC monitor outputs
	output [11:0] ad_a0,
	output [11:0] ad_a1,
	output [11:0] ad_b0,
	output [11:0] ad_b1,
	output ad_strobe,
	

	// External Current Control Input
	input	 logic  [2:0] iset, // Current target in unit amps  
	
	// Input clock, reset
	input logic clk,
	input logic reset
	
);

	// Module Item(s)


// System State machine

parameter S_IDLE   		= 0;
parameter S_CHARGE  		= 1;
parameter S_READY   		= 2;
parameter S_FIRE    		= 3;
parameter S_DISCHARGE  	= 4;
parameter S_OCP    		= 5;



logic fire_debounce;
logic igniter_burnout;
logic cap_over_current;
logic cap_under_voltage;
logic 		 adc_valid;


logic [3:0] state_q;

always @(posedge clk) begin : _launch_sm
	if( reset ) begin
		state_q <= S_IDLE;
	end else begin
		case( state_q ) 
		S_IDLE : 
			begin
				if( arm_button ) begin
					state_q <= S_CHARGE; // Advance to charge state
				end else begin
					state_q <= S_IDLE; 
				end
			end
		S_CHARGE :
			begin
				if( lt3420_done ) begin
					state_q <= S_READY;
				end else begin
					state_q <= S_CHARGE;
				end
			end
		S_READY :
			begin
				if( fire_button ) begin
					state_q <= S_FIRE;
				end else begin
					state_q <= S_READY;
				end
			end
		S_FIRE :
			begin
				if( fire_debounce && !fire_button ) begin
					state_q <= S_DISCHARGE;
				end else if( adc_valid && igniter_burnout ) begin
					state_q <= S_DISCHARGE; // igniter burned out
				end else if( adc_valid && cap_over_current ) begin
					state_q <= S_OCP; // over current
				end else if( adc_valid && cap_under_voltage ) begin
					state_q <= S_DISCHARGE; // cap is empty
				end else begin
					state_q <= S_FIRE;
				end
			end
		S_DISCHARGE :
			begin
				if( !arm_button ) begin
					state_q <= S_IDLE; // Reset 
				end else begin
					state_q <= S_DISCHARGE; // terminal state
				end
			end
		S_OCP :
			begin
				if( !arm_button ) begin
					state_q <= S_IDLE; // Reset 
				end else begin
					state_q <= S_OCP; // terminal state
				end
			end
		default :
			begin
				state_q <= S_IDLE;
			end
		endcase
	end
end

// Debounce, 10ms  fire button release.
// Fire button depressed is acted on immediately.
// After debounce period the first rire button release will terminate the fire sequence. 

parameter DEBOUNCE = 22'h00_0040; // 22'h3F_FFFF ; // 48Mhz / 10ms = 4.8 million cycles. Just use 22 bit countdown;

reg [21:0] debounce_div;
always @(posedge clk) begin
	if( reset ) begin
		debounce_div <= DEBOUNCE;
	end else if( state_q == S_FIRE ) begin
		debounce_div <= ( debounce_div == 22'd0 ) ? 22'd0 : debounce_div - 22'd1;
	end else begin
		debounce_div <= debounce_div;
	end
end
 
assign fire_debounce = ( debounce_div == 2'd0 ) ? 1'b1 : 1'b0;

// Capcitor Charger Control

assign lt3420_charge = (state_q == S_CHARGE || state_q == S_READY ) ? 1'b1 : 1'b0;


// Just use 24 bit counter, 16m cycles, use MSB for 3 Hz

reg [24:0] blink_div;
always @(posedge clk) begin
	if( reset ) begin
		blink_div <= 24'd0;
	end else begin
		blink_div <= blink_div + 24'd1;
	end
end

logic blink;
assign blink = blink_div[23];

// ARM Led

assign arm_led = (state_q == S_FIRE   ) ? 1'b1 :
					  (state_q == S_READY  ) ? 1'b1 : 
					  (state_q == S_CHARGE ) ? blink : 1'b0;

// Continuity, pulled low if an igniter present

assign cont_led = (cont) ? blink : 1'b1;

// ADC sample pulse

parameter ADC_CYCLES = 5'd16; // 16 for 48Mhz, 15 for 45Mhz to give a 3Mhz sample rate. 
										// CS is active low for 14 cycles to give a 12 bit output

reg [4:0] sample_div;
always @(posedge clk) begin
	if( reset ) begin
		sample_div <= ADC_CYCLES - 5'd1;
	end else if( 1/*state_q == S_FIRE*/ ) begin
		sample_div <= (sample_div == 0) ? (ADC_CYCLES - 5'd1) : sample_div - 5'd1;
	end else begin
		sample_div <= sample_div;
	end
end

assign ad_cs = ( /*state_q == S_FIRE &&*/ sample_div == 5'd0 ) ? 1'b1 : 1'b0;

// CS pipeline to trigger everything
logic [20:0] cs_delay;
always @(posedge clk) begin
	if( reset ) begin
		cs_delay[20:0]     <= 21'd0;
   end else begin
		// shift chain for the chip select
		cs_delay[20:0]  <= { cs_delay[19:0], ad_cs };		
	end
end

// DATA Input Receiver

logic [11:0] ad_load_a0, ad_load_a1, ad_load_b0, ad_load_b1;
logic [11:0] ad_hold_a0, ad_hold_a1, ad_hold_b0, ad_hold_b1;

logic [11:0] load;

parameter LOAD_SEL = 0;   // select first load delay, load reg input (ie 1 cycle early).
parameter HOLD_SEL = 13;  // select output hold delay bit
parameter VALID_SEL = 14;   // the cycle the adc hold registers are updatead

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

assign adc_valid = cs_delay[VALID_SEL];

// Monitor outputs
assign ad_a0 = ad_hold_a0;
assign ad_a1 = ad_hold_a1;
assign ad_b0 = ad_hold_b0;
assign ad_b1 = ad_hold_b1;
assign ad_strobe = adc_valid;

// ADC Mapping

logic [11:0] vcap, icap, vout, iout;

assign vcap[11:0] = ad_hold_b1;	// F9.2 0.0 to 511.75 volts (1/4 volt)
assign icap[11:0] = ad_hold_b0;	// F4.8 0.0 to 15.992 amps (1/256 amp)
assign vout[11:0] = ad_hold_a1;	// F9.2 0.0 to 511.75 volts
assign iout[11:0] = ad_hold_a0;	// F4.8 0.0 to 15.992 amps
                                               
// PWM Motor Control
// Very Simple initially +/-12.5% margin

logic [11:0] lower_margin, upper_margin;
logic [11:0] iout_est; // estimated

assign lower_margin = {1'b0, iset[2:0], 8'b0000_0000} - {4'b0000, iset[2:0], 5'b0_0000 };
assign upper_margin = {1'b0, iset[2:0], 8'b0000_0000} + {4'b0000, iset[2:0], 5'b0_0000 };

always @(posedge clk) begin
	if( reset ) begin
		pwm  <= 0;
	end else begin
		if( state_q != S_FIRE ) begin
			pwm <= 1'b0;
		end else if( pwm == 0 && iout_est <= lower_margin ) begin
			pwm <= 1'b1;
		end else if( pwm == 1 && iout_est >= upper_margin ) begin
			pwm <= 1'b0;
//		end else if( !adc_valid ) begin
//			pwm <= pwm;
//		end else if( pwm == 0 && iout <= lower_margin ) begin
//			pwm <= 1'b1;
//		end else if( pwm == 1 && iout >= upper_margin ) begin //  pwm == 1
//			pwm <= 1'b0;
		end else begin
			pwm <= pwm;
		end
	end
end

// Burn Through Detect
// Output with no current and rasied voltage indicates igniter burnt through.

parameter BURNOUT_VOLTAGE = 200 * 4;	// 200 V
parameter BURNOUT_CURRENT = 256 / 20;  // 50mA  
parameter CAP_CURRENT_LIMIT = 15 * 256; // 15 Amp limit
parameter CAP_VOLTAGE_LIMIT = 12 * 4; 	// 12 Volts

assign igniter_burnout = ((vout >= BURNOUT_VOLTAGE) && (iout <= BURNOUT_CURRENT) ) ? 1'b1 : 1'b0;  

assign cap_over_current = ( icap >= CAP_CURRENT_LIMIT ) ? 1'b1 : 1'b0;

assign cap_under_voltage = ( vcap < CAP_VOLTAGE_LIMIT ) ? 1'b1 : 1'b0;



// Self Discharge. If still powered and firing is done assert turn off 

assign dump = (state_q == S_DISCHARGE) ? 1'b1 : 1'b0;

// Audio Output

assign speaker = 1'b0;


// Current Model assignments and accumulator
// Multiply by 1/Lf
logic [33:0] iest_corr, iest_cur, iest_hold, iest_next, i_acc;
logic [12:0] deltav;
logic [29:0] deltai;

// Coil Model
// Calc deltav across the coil (depends on PWM ) --> signed(10.3)
assign deltav[12:0] = ( ( pwm ) ? { 1'b0, vcap[11:0] } : 13'h0000 ) - { 1'b0, vout[11:0] };
// Scaled by 1/Cf --> signed(27.3) to by shifted >> 30
assign deltai[29:0] = $signed( deltav[12:0] ) * $signed( { 1'b0, 16'd57358 } );

// When samples come in, get difference from model at that time (iest_prev)
assign iest_corr[33:0] = ( !adc_valid ) ? 34'b0 : ( {iout[11:0],22'h00_0000} - iest_hold[33:0]); // correction to be added

// Iest current is signed 4.30
assign iest_next[33:0] = i_acc[33:0] + {{4{deltai[29]}}, {3{deltai[29]}}, deltai[29:3] } + iest_corr[33:0];
	


// current accumulator
always @(posedge clk) begin
	if( reset ) begin
		i_acc <= 34'b0;
		iest_hold <= 3'b0;
	end else begin		
		i_acc <= iest_next;
		iest_hold <= ( cs_delay[LOAD_SEL] ) ? iest_next : iest_hold; // Hold the model at ADC sample time
	end
end


assign iout_est[11:0] = (  state_q == S_FIRE ) ? i_acc[33:22] : 0;

endmodule
