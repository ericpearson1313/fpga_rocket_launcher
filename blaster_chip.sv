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
	
	// Bank 1A: Analog Inputs / IO
	input [8:1] anain,
	
	// Bank 7, future serial port
	input [6:0] digio,
	
	// Bank 1B Rs232
	input 		rx232,
	output 		tx232,
	
	// High Voltage 
	output logic lt3420_charge,
	input  logic lt3420_done,
	output logic pwm,	
	output logic dump,
	input  logic cont_n,
	
	// External A/D Converters (2.5v)
	output logic        ad_cs,
	output logic		  ad_sclk,
	input  logic  [1:0] ad_sdata_a,
	input  logic  [1:0] ad_sdata_b,
	input  logic        CIdiag,
	input  logic        CVdiag,
	input  logic        LIdiag,
	input  logic 		  LVdiag,
	
	// External Current Control Input
	input	 logic  [2:0] iset, // Current target in unit amps  
	
	// SPI8 Bus
	inout  wire [7:0]  spi8_data_pad,   //   pad_io.export
	output logic spi_clk0,
	output logic spi_ncs,
	inout  wire  spi_ds,
	output logic spi_nrst,
	
	// HDMI Output 1 (Tru LVDS)
	output logic		hdmi_d0,
	output logic		hdmi_d1,
	output logic		hdmi_d2,
	output logic      hdmi_ck,

	// HDMI Output 2 (Tru LVDS)
	output logic		hdmi2_d0,
	output logic		hdmi2_d1,
	output logic		hdmi2_d2,
	output logic      hdmi2_ck,
	
	// Input clock, reset
	output logic clk_out, // Differential output
	input logic clk_in,	// Reference 48Mhz or other
	input logic reset_n
);



// PLL (only 1 PLL in E144 package!)

logic clk;	// global 48Mhz clock
logic clk4; // global 192MhZ spi8 clk
logic hdmi_clk; 	// Pixel clk, apparentlyi can support 720p
logic hdmi_clk5;  // 5x pixel clk clock for data xmit, 10b*3=30/3lanes=10ddr=5 

spi8_pll _spll(
	.inclk0 (clk_in),		// External clock input
	.c0     (clk_out), 	// External clock output differential
	.c1	  (clk),			// Global Clock ADC rate 48 Mhz
	.c2	  (clk4),		// Global Clock SPI8 rate 192 Mhz
	.c3	  (hdmi_clk),	// HDMI pixel clk
	.c4	  (hdmi_clk5)  // HDMI ddr clock 5x
	);
	
assign spi_clk0 = clk4;
assign ad_sclk  = clk;


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




logic int_reset;
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

// SPI 8 Memory interface

	logic [15:0] spi_dout; 
	logic [15:0] spi_din;       
	logic spi_oe;       

	spi8ddr _spi8ddr (
		.inclock         (clk4),    //  inclock.export
		.outclock        (clk4),    // outclock.export
		.dout            (spi_dout[15:0]),        //     dout.export
		.din             (spi_din[15:0]),         //      din.export
		.pad_io          (spi8_data_pad),      //   pad_io.export
		.oe              ({8{spi_oe}})           //       oe.export
	);

// HDMI DDR LVDS Output

	logic [7:0] hdmi_data;
	assign hdmi_data[1:0] = 2'b10;
		
	hdmi_out _hdmi_out (
		.outclock( hdmi_clk5 ),
		.din( hdmi_data ),
		.pad_out( {hdmi_d2, hdmi_d1, hdmi_d0, hdmi_ck} ), 
		.pad_out_b( )  // true differential, _b not req
	);

// HDMI DDR LVDS Output

	logic [7:0] hdmi2_data;
	assign hdmi2_data[1:0] = 2'b10;
	
	hdmi_out _hdmi2_out (
		.outclock( hdmi_clk5 ),
		.din( hdmi2_data ),
		.pad_out( {hdmi2_d2, hdmi2_d1, hdmi2_d0, hdmi2_ck} ), 
		.pad_out_b( )  // true differential, _b not req
	);
	
endmodule

