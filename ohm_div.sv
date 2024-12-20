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
	logic [0:14] del_valid;
	always @(posedge clk) begin
		if( reset ) begin
			{ valid_out, del_valid } <= 0;
		end else begin
			{ valid_out, del_valid } <= { del_valid, valid_in };
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

always @(posedge clk) begin
	r_out[11:0] = ( valid_out ) ? { 1'b0, (|quotient[29:19])?11'h000 : (quotient[18-:11] ^ 11'h7FF) } : r_out;	
end

endmodule
	



