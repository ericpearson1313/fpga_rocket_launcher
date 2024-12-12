module model_coil
(
	// Input clock, reset
	input logic clk,
	input logic reset,	
	// ADC voltage inputs (sample and held )
	input logic [11:0] vcap, // ADC native signed format. +-401V gives -+2000DN
	input logic [11:0] vout, // -.2005V/DN, about 5 digital number steps per volt
	// PWM signal 
	input logic pwm,
	// Esimated Coil current 
	output [11:0] iest_coil // +-10A = -+2050 + 2048, so 205DN/A 
);

// Current Model assignments and accumulator
// Multiply by 1/Lf
logic [36:0] iest_cur, iest_hold, iest_next, i_acc;

/////////////////////////
// Coil Current Model
/////////////////////////

// Remove ADC offset and flip  polarity of Voltage inputs
logic [11:0] vcap_corr;
logic [11:0] vout_corr;
assign vcap_corr[11:0] = vcap[11:0] ^ 12'h7FF;
assign vout_corr[11:0] = vout[11:0] ^ 12'h7FF;

// Calc deltaV across the coil (depends on PWM )
logic [12:0] deltav;
assign deltav[12:0] = ( ( pwm ) ? { vcap_corr[11], vcap_corr[11:0] } : 13'h0000 ) - { vout_corr[11], vout_corr[11:0] };

// Scaled by (1<<30)/(L*f) --> signed(27.3) to by shifted >> 30
logic [29:0] deltai;
always_comb begin : _lf_mult
	deltai[29:0] = $signed( deltav[12:0] ) * $signed( { 1'b0, 16'd57358 } );
end
// Iest current is signed 4.30
assign iest_next[36:0] = i_acc[36:0] + {{7{deltai[29]}}, deltai[29:0] };
	
// current accumulator
always @(posedge clk) begin
	if( reset ) begin
		i_acc <= 37'b0;
	end else begin	
			if( pwm && !deltai[29] || !pwm && deltai[29] ) begin // if moving in correct direction
				if( iest_next[36] ) begin // clip if current is negative
					i_acc <= 37'b0;
				end else begin
					i_acc <= iest_next;
				end
			end else begin
				i_acc <= i_acc;
			end
	end
end

// Scale current estimation to ADC current units
// 42089 = ( 0.2005V/DN * 205DN/A + 0.5 ) << 10
logic [35:0] current;
always @(posedge clk) begin : _i_mult
	current[35:0] <= $signed( i_acc[36:19] ) * $signed( { 2'b00, 16'd42089 } );
end

// do the offset flip to match adc format
assign iest_coil[11:0] = current[35:24] ^ 12'h7FF;

endmodule // model_coil