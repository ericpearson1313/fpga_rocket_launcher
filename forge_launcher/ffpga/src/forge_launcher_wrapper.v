// Top level Chip Wrapper
(* top *) module forge_launcher_wrapper
(
// Forge FPGA built in clk reset
(* iopad_external_pin, clkbuf_inhibit *) input logic clk,
(* iopad_external_pin *) input logic resetn,


	// Input Buttons
(* iopad_external_pin *)	input  logic arm_button,
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
(* iopad_external_pin *)	output logic		ad_sclk,
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

    // PLL Control, 48 Mhz
    assign pll_en = 1'b1;
    assign pll_refdiv = 6'b00_0001;		// Equivalent value in decimal form 6'd1,
    assign pll_fbdiv = 12'b0000_0001_1000;	// Equivalent value in decimal form 12'd24,
    assign pll_postdiv1 = 3'b101;		// Equivalent value in decimal form 3'd5,
    assign pll_postdiv2 = 3'b101;		// Equivalent value in decimal form 3'd5,
    assign pll_bypass = 1'b0;
    assign pll_clk_selection = 1'b0;

	// Synchronize reset
	logic reset;
	logic [3:0] reset_shift = 4'b0; // initial value upon config is reset
	always_ff @(posedge clk)
		{ reset, reset_shift[3:0] } <= { !reset_shift[3], reset_shift[2:0], resetn };

	// create ADC inverted clk for output
	logic ad_sclk_en;
	always_ff @(posedge clk)
		ad_sclk_en <= resetn;
	assign ad_sclk  = (!clk & ad_sclk);

	forge_launcher _chip (
		// System
		.clk			( clk ),
		.reset			( reset ),
		// Front Panel
		.fire_button 	( fire_button ),
		.arm_button 	( arm_button ),
		.arm_led 		( arm_led ),
		.cont_led	 	( cont_led ),
		.speaker 		( speaker ),
		// High Voltage
		.lt3420_charge 	( lt3420_charge ),
		.lt3420_done   	( lt3420_done   ),
		.pwm           	( pwm ),
		.dump			( dump ),
		// ADC interface
		.ad_cs			( ad_cs ),
		.ad_sdata_a 	( ad_sdata_a ),
		.ad_sdata_b 	( ad_sdata_b ),
		// Tie off Debug inputs
		.iset			( 3'b111 ),
		.key			( 5'b00000 )
    );
endmodule // forge_launcher_wrapper 
		
		
		
