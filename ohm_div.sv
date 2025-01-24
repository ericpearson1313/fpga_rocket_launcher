
// Resitance Calc Module
// Enable input assertion, creates a PWM pulse (2us), and 64K hold-off on retrigger
// waits for a valid resistance calc (64 cycles), and then accumulates for total 128 cycles
// At each power of two an output resistance is provided. Output is latched.

module igniter_resistance
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
	output led,
	output energy, // high when power accumulation should occur
	
	// Resistance Output
	output logic valid_out,
	output logic [11:0] r_out // adc format, +ve only
);
	
	// Triggering with 0.6 Sec holdoff
	logic [24:0] holdoff;
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
	logic [17:0] acc; // max 128 samples of 11 bits
	logic [7:0] cnt;
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
			led <= ( holdoff == 4097 ) ? ((( r_out ^ 12'h7ff ) >= 12'h020 &&  ( r_out ^ 12'h7ff ) < 12'h200 ) ? 1'b1 : 1'b0 ) : led;
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
	logic first;				  
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
// R = E / I
// R = E * 205 dn/A * .2005 V/Dn / I 
// R = ( |E[11:0]| * 16'd42089 ) / max( 1, I ) >> 10
// Inputs need conversion from ADC format
// Hardcoded for launch controller adc scale
// divider runs at 2 bits/cycle

module ohm_div
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


// fixed delay pipeline 16
// 1 cycle to load, 15 cycles of processing
	logic [15:0] del_valid;
	always @(posedge clk) begin
		if( reset ) begin
			del_valid <= 0;
		end else begin
			del_valid  <= { del_valid[14:0], valid_in };
		end
	end

// I (current Input)

logic [0:3][13:0] denom;
logic [10:0] current; // in ADC units
assign current[10:0] = ( i_in[11] | i_in[10:0] == 11'h7FF ) ? 11'h001 : ( i_in[10:0] ^ 11'h7FF );
always @(posedge clk) begin
	if( reset ) begin
		denom <= 0;
	end else begin
		if( valid_in ) begin
		   denom[0][13:0] <= 0;
			denom[1][13:0] <= { 3'b000, current[10:0] };
			denom[2][13:0] <= { 3'b000, current[10:0] }        + { 3'b000, current[10:0] };
			denom[3][13:0] <= { 2'b00 , current[10:0] , 1'b0 } + { 3'b000, current[10:0] };				
		end else begin
			denom <= denom;
		end
	end
end
	
// Voltage Input
// clip -ve to zero and format for input
logic [11:0] voltage; // in adc units
assign voltage = ( v_in[11] ) ? 11'h000 : ( v_in[10:0] ^ 11'h7ff );
logic [26:0] vscale; // scaled to normalize units << 10 precision
assign vscale[26:0] = voltage * 16'd42089;

// Numerator is 38 bits = 27 num + 11 denom + 1 
logic [38:0] numer;
// Divide steps and remainder
logic [0:3][13:0] remd; // remainder per q
logic [13:0] rem;
assign remd[0][13:0] = numer[38-:14] - denom[0][13:0]; // dummy
assign remd[1][13:0] = numer[38-:14] - denom[1][13:0];
assign remd[2][13:0] = numer[38-:14] - denom[2][13:0];
assign remd[3][13:0] = numer[38-:14] - denom[3][13:0];
assign rem[13:0] = ( !remd[3][13] ) ? remd[3] :
                   ( !remd[2][13] ) ? remd[2] :
						 ( !remd[1][13] ) ? remd[1] : remd[0] ;

// Numerator shift, and accumulate
logic [29:0] quotient;
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
			quotient[1:0] <= ( !remd[3][13] ) ? 2'b11 :
			                 ( !remd[2][13] ) ? 2'b10 :
			                 ( !remd[1][13] ) ? 2'b01 : 2'b00 ;
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

always @(posedge clk) begin
	valid_out   <= ( del_valid[15] && denom[1] > 32 ) ? 1'b1 : 1'b0;
	r_out[11:0] <= ( del_valid[15] && denom[1] > 32 ) ? { 1'b0, (|quotient[29:19])?11'h000 : (quotient[18-:11] ^ 11'h7FF) } :
                  ( del_valid[15] ) ? 12'h7FF : r_out;	
end

endmodule
	



