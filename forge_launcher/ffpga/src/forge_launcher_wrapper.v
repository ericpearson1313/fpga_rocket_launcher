// Top level Chip Wrapper
(* top *) module forge_launcher_wrapper
(
// Forge FPGA built in clk reset
(* iopad_external_pin, clkbuf_inhibit *) input logic clk2x, // 2x from PLL
(* iopad_external_pin, clkbuf_inhibit *) input logic clk,   // from LAC 0
(* iopad_external_pin *) 	output clk_toggle, 					// toggle reg = clk output to LAC
(* iopad_external_pin *) 	output logic_as_clk0_en,			// enable Logic as clock
(* iopad_external_pin *) 	input  logic resetn,

	// Input Buttons
//(* iopad_external_pin *)	input  logic arm_button,
(* iopad_external_pin *)	input  logic fire_button,

	// Output LED/SPK
(* iopad_external_pin *)	output logic arm_led,
(* iopad_external_pin *)	output logic cont_led,
(* iopad_external_pin *)	output logic speaker,

	// High Voltage 
(* iopad_external_pin *)	output logic lt3420_charge,
(* iopad_external_pin *)	input  logic lt3420_done,
(* iopad_external_pin *)	output logic pwm,	
(* iopad_external_pin *)	output logic dump,
	
	// External A/D Converters (2.5v)
(* iopad_external_pin *)	output logic        ad_cs,
(* iopad_external_pin *)	output logic		ad_sclk, // ~clk, not used internally
(* iopad_external_pin *)	input  logic  [1:0] ad_sdata_a,
(* iopad_external_pin *)	input  logic  [1:0] ad_sdata_b,


	// Forge PLL control
(* iopad_external_pin *) output pll_en,
(* iopad_external_pin *) output [5:0] pll_refdiv,
(* iopad_external_pin *) output [11:0] pll_fbdiv,
(* iopad_external_pin *) output [2:0] pll_postdiv1,
(* iopad_external_pin *) output [2:0] pll_postdiv2,
(* iopad_external_pin *) output pll_bypass,
(* iopad_external_pin *) output pll_clk_selection

);

    // PLL Control, 2 x 24 Mhz = 48 Mhz
  assign pll_en = 1'b1;
    assign pll_refdiv = 6'b00_0001;		// Equivalent value in decimal form 6'd1,
    assign pll_fbdiv = 12'b0000_0001_1000;	// Equivalent value in decimal form 12'd24,
    assign pll_postdiv1 = 3'b101;		// Equivalent value in decimal form 3'd5,
    assign pll_postdiv2 = 3'b101;		// Equivalent value in decimal form 3'd5,
    assign pll_bypass = 1'b0;
    assign pll_clk_selection = 1'b0;
    
    // Enable LAC 0
    assign logic_as_clk0_en = 1'b1;

	//  flops create half rate clk and ad_sclk = !clk;
	logic toggle;
	logic clk_toggle;
	logic sclk_toggle;
	always_ff @(posedge clk2x) begin 
		toggle <= !toggle;
		clk_toggle 	<= toggle; // To embend in the IOB FF for REF_LAC_0
		sclk_toggle <= toggle; // before inversion/phase delay 
		ad_sclk 	<= sclk_toggle; // inverted to embed in the IOB FF for ad_sclk
	end
	
	// Synchronize reset
	logic reset;
	logic [3:0] reset_shift = 4'b0; // initial value upon config is reset
	always_ff @(posedge clk)
		{ reset, reset_shift[3:0] } <= { !reset_shift[3], reset_shift[2:0], resetn };
		
	// Explicit Insert some slow IOB output flops (reduce warnings)
	logic speaker_d;
	logic arm_led_d;
	logic cont_led_d;
	logic lt3420_charge_d;
	logic dump_d;
	always_ff @(posedge clk) speaker <= speaker_d;
	always_ff @(posedge clk) arm_led <= arm_led_d;
	always_ff @(posedge clk) cont_led <= cont_led_d;
	always_ff @(posedge clk) lt3420_charge <= lt3420_charge_d;
	always_ff @(posedge clk) dump <= dump_d;
	
	// Explicity Insert some slow IOB input flops
	logic fire_button_q;
	logic lt3420_done_q;
	always_ff @(posedge clk) fire_button_q <= fire_button;
	always_ff @(posedge clk) lt3420_done_q <= lt3420_done;
	
	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	// Physical parameters
	parameter CLOCK_FREQ_MHZ = 24;  // 48 or 24 Mhz
	parameter COIL_IND_UH = 390;
	
	forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) _chip (
		// System
		.clk			( clk ),
		.reset			( 1'b0 ), // fpga starts as configured?!!?
		// Front Panel
		.fire_button 	( fire_button_q ),
		.arm_led 		( arm_led_d ),
		.cont_led	 	( cont_led_d ),
		.speaker 		( speaker_d ),
		// High Voltage
		.lt3420_charge 	( lt3420_charge_d ),
		.lt3420_done   	( lt3420_done_q   ),
		.pwm           	( pwm ),
		.dump			( dump_d ),
		// ADC interface
		.ad_cs			( ad_cs ),
		.ad_sdata_a 	( ad_sdata_a ),
		.ad_sdata_b 	( ad_sdata_b ),
		// Tie off Debug inputs
		.iset			( 3'b011 ), // { !autorun, use_est , mute }
		.key			( 5'b00000 )
    );
endmodule // forge_launcher_wrapper 
		
		
		
