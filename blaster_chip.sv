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
	
	// Charger
	input  logic lt3420_done,
	output logic lt3420_charge,

	// Voltage Controls
	output logic pwm,
	output logic dump,

	// Continuity feedback
	input  logic cont_n,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	input  logic  [1:0] ad_sdata_a,
	input  logic  [1:0] ad_sdata_b,

	// External Current Control Input
	input	 logic  [2:0] iset, // Current target in unit amps  
	
	// Input clock, reset
	input logic clk_in,
	output logic clk_out,
	input logic reset_n
);



// Clock , direct connect now, pll later

logic clk;
assign clk = clk_in; // use external clock
assign clk_out = clk_in; // loop to ADC, which uses the -ve edge.


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

assign int_reset = (reset_shift[3:0] != 4'hF) ? 1'b1 : 1'b0; // reset de-asserted after all bit shifted in 

// LEDs active low
logic arm_led;
logic cont_led;
assign arm_led_n = !arm_led;
assign cont_led_n = !cont_led;

// Continuity active low
logic cont;
assign cont = !cont_n;

// Speaker is differential out gives 6Vp-p
assign speaker_n = !speaker;

blaster _blaster (
	// Input Buttons
	.arm_button( arm_button ), // arm is the power button, does this make sense
	.fire_button( fire_button ), // active high

	// Output LED/SPK
	.arm_led( arm_led ),
	.cont_led( cont_led ),
	.speaker( speaker ),
	
	// Charger
	.lt3420_done( lt3420_done ),
	.lt3420_charge( lt3420_charge ),

	// Voltage Controls
	.pwm( pwm ),
	.dump( dump ),

	// Continuity feedback
	.cont( cont ),
	
	// Current setting
	.iset( iset  ),
	
	// External A/D Converters
	.ad_cs( ad_cs ),
	.ad_sdata_a( ad_sdata_a[1:0] ),
	.ad_sdata_b( ad_sdata_b[1:0] ),

	// Input clock
	.clk( clk ),
	.reset( int_reset )
);

endmodule

