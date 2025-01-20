// This is a digital model of the current in the output inductor.
// This model runs at 48 Mhz (vs 3 Mhz sample rate) and give
// 16x timing precision and lower latency.
// Inputs are the PWM signal and slowely varying 
// capacitor and output voltages.

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

// Remove ADC offset and flip  polarity of Voltage inputs
logic [11:0] vcap_corr;
logic [11:0] vout_corr;
assign vcap_corr[11:0] = ( vcap > 12'h7F8 ) ? 8 : ( vcap[11:0] ^ 12'h7FF ); // clip to >= 8, else model wanders
assign vout_corr[11:0] = ( vout[11] ) ? 0 : ( vout[11:0] ^ 12'h7FF ); // clip to zero if -ve

// Future: dead zone, filtering, and zero init

// Calc deltaV across the coil (depends on PWM )
logic [12:0] deltav;
assign deltav[12:0] = ( ( pwm ) ? ({ vcap_corr[11], vcap_corr[11:0] }) : 13'h0000 ) - { vout_corr[11], vout_corr[11:0] };

// Scaled by (1<<30)/(L*f) --> signed(27.3) to by shifted >> 30
logic [29:0] deltai;
assign deltai[29:0] = $signed( deltav[12:0] ) * $signed( { 1'b0, 16'd57358 } );

// Iest current is signed 4.30
assign iest_next[36:0] = i_acc[36:0] + {{7{deltai[29]}}, deltai[29:0] };
	
// current accumulator
always @(posedge clk) begin
	if( reset ) begin
		i_acc <= 37'b0;
	end else begin	
		if( iest_next[36] || iest_next[35:20] == 0 ) begin // clip to zero if small or -ve
			i_acc <= 0;
		end else begin
			i_acc <= iest_next;
		end
	end
end

// Scale current estimation to ADC current units
// 42089 = ( 0.2005V/DN * 205DN/A + 0.5 ) << 10
// can be unsigned mult 34b = 18b * 16b
logic [33:0] current;
always @(posedge clk) begin : _i_mult
	current[33:0] <= i_acc[36:19] * 16'd42089;
end

// Calc model current correction. Capture it at rise of pwm before any effect
logic [11:0] icor; 
logic pwm_del;
always @(posedge clk) begin
	pwm_del <= pwm;
	icor <= ( pwm & !pwm_del ) ? ( iout[11:0] ^ 12'h7ff ) - current[33-:12] : icor; // latch error at start of pwm cycle
end

// select the window (will always be positive)
assign iest_coil[11:0] = ( current[33-:12] + icor ) ^ 12'h7FF;

endmodule // model_coil