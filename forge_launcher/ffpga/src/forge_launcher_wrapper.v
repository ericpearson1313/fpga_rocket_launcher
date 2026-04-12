// vim: ts=4:
// Top level Chip Wrapper
(* top *) module forge_launcher_wrapper
(
// Forge FPGA built in clk reset
(* clkbuf_inhibit *) 	input logic clk2x, // 2x from PLL
(* clkbuf_inhibit *) 	input logic clk,   // from LAC 0
						output clk_toggle, 					// toggle reg = clk output to LAC
						output logic_as_clk0_en,			// enable Logic as clock
						output logic osc_en,


	// Input Buttons
//(* iopad_external_pin *)	input  logic arm_button,
(* iopad_external_pin *)	input  logic launch_n,
(* iopad_external_pin *)	input  logic mute_n,

	// Output LED/SPK
(* iopad_external_pin *)	output logic arm_led,
(* iopad_external_pin *)	output logic cont_led,
(* iopad_external_pin *)	output logic speaker,
						output logic arm_led_oe,
						output logic cont_led_oe,
						output logic speaker_oe,

	// High Voltage 
(* iopad_external_pin *)	output logic charge,
(* iopad_external_pin *)	output logic pwm,	
(* iopad_external_pin *)	output logic dump,
						output logic charge_oe,
						output logic pwm_oe,	
						output logic dump_oe,
	
	// External A/D Converters (2.5v)
(* iopad_external_pin *)	output logic    ad_cs,
(* iopad_external_pin *)	output logic		ad_sclk, // ~clk, not used internally
(* iopad_external_pin *)	input  logic  [1:0] ad_sdata_a,
(* iopad_external_pin *)	input  logic  [1:0] ad_sdata_b,
						output logic    ad_cs_oe,
						output logic		ad_sclk_oe, // ~clk, not used internally

	// Forge PLL control
						output pll_en,
						output [5:0] pll_refdiv,
						output [11:0] pll_fbdiv,
						output [2:0] pll_postdiv1,
						output [2:0] pll_postdiv2,
						output pll_bypass,
						output pll_clk_selection

);

    // PLL Control, 50 Mhz int Osc Ref,  2 x 48 Mhz = 96 Mhz out
     assign pll_en = 1'b1;
    assign pll_refdiv = 6'b00_0101;		// Equivalent value in decimal form 6'd5,
    assign pll_fbdiv = 12'b0000_1001_0000;	// Equivalent value in decimal form 12'd144,
    assign pll_postdiv1 = 3'b101;		// Equivalent value in decimal form 3'd5,
    assign pll_postdiv2 = 3'b011;		// Equivalent value in decimal form 3'd3,
    assign pll_bypass = 1'b0;
    assign pll_clk_selection = 1'b0;


    
    // Enable LAC 0
    assign logic_as_clk0_en = 1'b1;
    
    // Enable OSC
    assign osc_en = 1'b1;
    
    // Emab;e Ouput OEs
    assign ad_sclk_oe 	= 1'b1;
    assign ad_cs_oe 		= 1'b1;
    assign dump_oe 		= 1'b1;
    assign pwm_oe 		= 1'b1;
    assign charge_oe 	= 1'b1;
    assign speaker_oe	= 1'b1;
    assign cont_led_oe	= 1'b1;
    assign arm_led_oe	= 1'b1;

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

	// Explicit Insert some slow IOB output flops (specifically not flopping PWM singal)
	/*
	logic speaker_d;
	logic arm_led_d;
	logic cont_led_d;
	logic charge_d;
	logic dump_d;
	always_ff @(posedge clk) speaker <= speaker_d;
	always_ff @(posedge clk) arm_led <= arm_led_d;
	always_ff @(posedge clk) cont_led <= cont_led_d;
	always_ff @(posedge clk) charge <= charge_d;
	always_ff @(posedge clk) dump <= dump_d;
	*/
	
	// Explicity Insert some slow IOB input flops
	logic launch_nq;
	logic mute_nq;
	always_ff @(posedge clk) launch_nq <= launch_n;
	always_ff @(posedge clk) mute_nq <= mute_n;
	
	// ADC Scale parameters
	parameter ADC_VOLTS_PER_DN = 0.2005;
	parameter ADC_DN_PER_AMP = 205;
	// Physical parameters
	parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
	parameter COIL_IND_UH = 390;
	
	forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) i_chip (
		// System
		.clk				( clk ),
		.reset			( 1'b0 ), // fpga starts in reset state
		// Front Panel
		.fire_button 	( !launch_nq ),
		.arm_led 		( arm_led ),
		.cont_led	 	( cont_led ),
		.speaker 		( speaker ),
		// High Voltage
		.lt3420_charge 	( charge ),
		.lt3420_done   	( 1'b0  ),
		.pwm           	( pwm ),
		.dump			( dump ),
		// ADC interface
		.ad_cs			( ad_cs ),
		.ad_s_iout		( ad_sdata_a[0] ),
		.ad_s_vout		( ad_sdata_b[1] ),
		.ad_s_vcap		( ad_sdata_a[1] ),
		.neg_iout		( 1'b0 ),
		.neg_vout		( 1'b0 ),
		.neg_vcap		( 1'b0 ),
		// Tie off Debug inputs
		.auto_mode		( 1'b0 ),
		.use_est			( 1'b1 ),
		.mute			( !mute_nq ),
		.key				( 5'b00000 )
    );
endmodule // forge_launcher_wrapper 
		
		
		
