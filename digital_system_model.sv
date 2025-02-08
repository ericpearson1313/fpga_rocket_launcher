// This is a digital model of the current in the output inductor.
// This model runs at 48 Mhz (vs 3 Mhz sample rate) and give
// 16x timing precision and lower latency.
// Inputs are the PWM signal and slowely varying capacitor and output voltages. 
// The measured iout is also provided to intialize the model pon PWM rising edge
// The model is ideal and optimisitic and will undershoot the current.

module model_coil
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

// Current Model assignments and accumulator
// Multiply by 1/Lf
logic [36:0] iest_cur, iest_hold, iest_next, i_acc;

/////////////////////////
// Coil Current Model
/////////////////////////

// Pre-process adc cap and output voltages (format, clip to zero with deadzone
logic [11:0] vcap_corr;
logic [11:0] vout_corr;
assign vcap_corr[11:0] = ( vcap > 12'h7F8 ) ? 8 : ( vcap[11:0] ^ 12'h7FF ); // clip to >= 8, else model wanders
assign vout_corr[11:0] = ( vout[11] ) ? 0 : ( vout[11:0] ^ 12'h7FF ); // clip to zero if -ve

// Calc deltaV across the coil (depends on PWM )
// deltav = ( pwm ) ? vcap : 0 ) - vout: UNIT: s13 .2005 V/dn
logic [12:0] deltav;
assign deltav[12:0] = ( ( pwm ) ? ({ vcap_corr[11], vcap_corr[11:0] }) : 13'h0000 ) - { vout_corr[11], vout_corr[11:0] };

// Scale the ADC voltage difference to an ADC current difference
// - deltav scaled to volts * 0.2005 V/DN
// - Delta I calculated = 1/(L*F) = 1/(390uH*48Mhz) in Amps
// - Delta I scaled to ADC units * 205DN/A
// - 16'd36837 = .2005 V/dn / ( 48 Mhz * 390 uH ) * 205 dn/A << 24
// signed multipley s13 * s17 = s30 (16+1) >> 24

logic [29:0] deltai;
assign deltai[29:0] = $signed( deltav[12:0] ) * $signed( { 1'b0, 16'd36837 } );

// Iest current is signed 12.24 in ADC current DN scale
assign iest_next[35:0] = i_acc[35:0] + { {6{deltai[29]}}, deltai[29:0] };
	
// current accumulator
logic pwm_del;
always @(posedge clk) pwm_del <= pwm;
always @(posedge clk) begin
	if( reset ) begin
		i_acc[35:0] <= 36'b0;
	end else if( pwm & ~pwm_del ) begin // load read value on pwm rise.
		i_acc[35:0] <= { ( iout[11] ) ? 12'h0 : ( iout[11:0] ^ 12'h7ff ), 24'h00_0000 };
	end else if ( iest_next[35] || iest_next[35-:25] == 0 ) begin // clip to zero if small or -ve
		i_acc[35:0] <= 0;
	end else begin
		i_acc[35:0] <= iest_next; // default load next
	end
end

// Ouput estimate is in adc units 
assign iest_coil[11:0] = i_acc[35-:12] ^ 12'h7ff;

endmodule // model_coil