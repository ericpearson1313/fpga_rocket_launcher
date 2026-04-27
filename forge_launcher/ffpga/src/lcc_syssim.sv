// vim: ts=4:
// Inteteger model for synthesizable system simulation.
// To be part a an FGPA impremented chip tester.

`timescale 1ns / 1ps
// Primary synthesiable model of the coil current and capacitor energy
// intgration of coil current and cap energy are done in extended fixed point ADC units
// Capcitor voltage is derived by LUT from cap voltage
// Output voltage is derived from current and conductage constants (1/R),
// Capacitor current is intermediate for cap energy calc

module lcc_syssim #(
	parameter	ADC_VOLTS_PER_DN	= 0.2005,
	parameter   ADC_DN_PER_JOULE	= 205,
	parameter	ADC_DN_PER_AMP		= 205,
	parameter	CLOCK_FREQ_MHZ		= 48, // clock in mhz
	parameter	COIL_UH				= 390, // coil in uH
	parameter 	CAP_UF				= 200,
	parameter   CH_RATE				= 30.0, // Joule/sec
	parameter   R_DUMP 				= 300.0 // Dump resistor in ohms
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
	
	logic [11:0] vout;
	logic [39:0] iout;
	logic [39:0] ecap;
	logic [11:0] icap;
	logic [11:0] vcap;

	localparam ADC_CHARGE_PER_CYCLE = ( CH_RATE * ADC_DN_PER_JOULE * (1<<30) ) / ( CLOCK_FREQ_MHZ * 1000000.0 );
	localparam ADC_DUMP_CONST = (1<<30) * ( ADC_DN_PER_JOULE / ( R_DUMP * CAP_UF * CLOCK_FREQ_MHZ ) );
	localparam ADC_COIL_CONST = (1<<30) / ( COIL_UH * CLOCK_FREQ_MHZ );
	localparam ADC_CAP_CONST  = (1<<30) * ( ADC_DN_PER_JOULE * ( ADC_VOLTS_PER_DN ) / ( ADC_DN_PER_AMP ) );

	// Cap Energy to voltage rom
	logic [11:0] vcap_rom [63:0]; // unsigned 6 MSBs as input
	initial begin
		for( int ee = 0; ee < 2048; ee+=32 )
			vcap_rom[ee>>5] = $sqrt( ( 2.0 * ee * 1000000.0 ) / ( ADC_DN_PER_JOULE * CAP_UF ) ) / ADC_VOLTS_PER_DN;
		/* synopsys translate_off */
		for( int ii = 0; ii < 64; ii++ ) 
			$display( "vcap_rom[%d] = %d, Ecap=%f J Vcap=%f V", ii, vcap_rom[ii], ii*32.0/ADC_DN_PER_JOULE, vcap_rom[ii]*ADC_VOLTS_PER_DN );
		$display("ADC_CHARGE_PER_CYCLE = %f", ADC_CHARGE_PER_CYCLE );
		$display("ADC_DUMP_CONST = %f", ADC_DUMP_CONST );
		$display("ADC_COIL_CONST = %f", ADC_COIL_CONST );
		$display("ADC_CAP_CONST = %f", ADC_CAP_CONST );
		/* synopsys translate_on */
	end
	always_ff @(posedge clk) vcap <= vcap_rom[ ecap[38-:6] ];

	// Cap current is just gated coil current
	always_ff @(posedge clk) icap <= ( pwm ) ? iout[39-:12] : 12'b0;

	// Model loop
	always_ff @(posedge clk) begin
		if( reset ) begin
			iout <= 40'd0;
			vout <= 12'd0;
			ecap <= 40'd0;
		end else if( dump ) begin
			iout <= 40'd0;
			vout <= 12'd0;
			ecap <= ecap - (((ecap) * ADC_DUMP_CONST) << (40-30));
		end else if( charge ) begin
			iout <= 40'd0;
			vout <= 12'd0;
			ecap <= ecap + ADC_CHARGE_PER_CYCLE;
		end else if( burn ) begin
			iout <= 40'd0;
			vout <= vcap;
			ecap <= ecap;
		end else if( pwm ) begin
			iout <= iout + ((( vcap - vout ) * ADC_COIL_CONST) << (40-30));
			ecap <= ecap - vcap * iout * ADC_CAP_CONST;
		end else /* !pwm */ begin
			iout <= iout - ((( vout ) * ADC_COIL_CONST) << (40-12-16));
			ecap <= ecap;
		end 
	end

	// connect up outputs
	assign ad_iout = iout[39-:12];
	assign ad_ecap = ecap[39-:12];
	assign ad_vout = vout;
	assign ad_icap = icap;
	assign ad_vcap = vcap;

endmodule
