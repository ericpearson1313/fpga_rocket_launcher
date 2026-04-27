// vim: ts=4:
// Inteteger model for synthesizable system simulation.
// To be part a an FGPA impremented chip tester.
`timescale 1ns / 1ps
module lcc_syssim #(
	parameter	ADC_VOLTS_PER_DN	= 0.2005,
	parameter   ADC_DN_PER_JOULE	= 205,
	parameter	ADC_DN_PER_AMP		= 205,
	parameter	CLOCK_FREQ_MHZ		= 48, // clock in mhz
	parameter	COIL_IND_UH			= 390 // coil in uH
	) (
		// system
		input logic clk,
		input logic reset,
		// hardware power control signals
		input logic dump,
		input logic charge,
		input logic pwm,
		// virtual simulaiton inputs
		input logic burn,
		// ADC outputs
		output logic [11:0] ad_iout,
		output logic [11:0] ad_vout,
		output logic [11:0] ad_vcap,
		// Monitoring outputs
		output logic [11:0] ad_icap,
		output logic [11:0] ad_ecap
	);
endmodule
