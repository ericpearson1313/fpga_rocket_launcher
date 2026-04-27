// vim: ts=4:
// top level launcher sim.
`timescale 1ns / 1ps
module lcc_tb( );

      	logic clk;
        logic reset;

        // Create 48 Mhz clock
        initial begin
                clk = 0;
                for( ;; ) begin
                        #(10.416ns);
                        clk = !clk;
                end
        end

        // Simulation Setup
        initial begin
        	$timeformat(-9, 0, "ns", 12); // 1: scale (ns=-9), 2: decimals, 3: suffix, 4: print-field width
        // configure FST (waveform) dump
        	$dumpfile("lcc.fst");
        	$dumpvars(1,i_dut);
		end


        // create reset
        initial begin
                reset = 1;
                for( int ii = 0; ii < 10; ii++ ) begin
                        @(negedge clk);
                end
                reset = 0;
                $display("Reset done");
                for( int ii = 0; ii < 2000*48000; ii++ ) begin // Max 2000 msec
                        @(negedge clk);
                end
                $display("Test terminated, exceeded MY time line");
                $finish();
        end

	////////////////////
    // DUT
	////////////////////

	// dut signals
	logic fire;
	logic pwm, dump;
	logic charge;
	logic n_cs;
	logic [3:0] data, data_n;
	logic arm_led, cont_led, speaker;
	logic mute;
		

    // ADC Scale parameters
    parameter ADC_VOLTS_PER_DN = 0.2005;
    parameter ADC_DN_PER_AMP = 205;
    // Physical parameters
    parameter CLOCK_FREQ_MHZ = 48;  // 48 or 24 Mhz
    parameter COIL_IND_UH = 390;

    forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) i_dut (
                // System
                .clk                    ( clk ),
                .reset                  ( 1'b0 ), // fpga starts in reset state
                // Front Panel
                .fire_button    		( fire),
                .arm_led                ( arm_led ),
                .cont_led               ( cont_led ),
                .speaker                ( speaker ),
                // High Voltage
                .lt3420_charge          ( charge ),
                .lt3420_done            ( 1'b0 ), // will use ADC measurement
                .pwm            	    ( pwm ),
                .dump                   ( dump ),
                // ADC interface
				.ad_cs					( n_cs ),
				.ad_s_vcap				( data[1] ),
				.ad_s_iout				( data[0] ),
				.ad_s_vout				( data[3] ),
				.neg_vcap			    ( 1'b0 ),
				.neg_vout			    ( 1'b0 ),
				.neg_iout			    ( 1'b0 ),
                // Set Static Control Inputs
				.auto_mode      ( 1'b1 ),
				.use_est		( 1'b1 ),
				.mute           ( mute ),
                .key            ( 5'b00000 )
    );
	
	
	// Operating Mode 
	localparam MSEC = CLOCK_FREQ_MHZ * 1000;
	logic burn;
	initial begin
		// hardware will wait till charged before firing;
		fire = 0;
		mute = 0;
		burn = 0;
		// charge shoudl start low
		$display("initial Charge state %d", charge);

		// charge automatically starts
		while( !charge ) @(negedge clk); // wait for charge to start
		$display("Charge started");

		while( charge ) @(negedge clk); // wait for charge to end 
		$display("Charge done, arm_led %b", arm_led );

		// Wait for continuity speaker tone
		while( !speaker ) @(negedge clk); // wait for charge to end 
		$display("Continuity tone, cont_led %b", cont_led );

		// wait a bit then lanuch
		for( int ii = 0; ii < 50*MSEC; ii++ ) @(negedge clk); 
		$display("Launch button press");
		fire = 1;

		// press for >5ms to debounce
		for( int ii = 0; ii < 6*MSEC; ii++ ) @(negedge clk); 
		$display("Release button ");
		fire = 0;

		// should see pwm on/off
		while( !pwm ) @(negedge clk); // wait for a pwm signal
		$display("PWM posedge seen");
		while( pwm ) @(negedge clk); // wait for a pwm signal
		$display("PWM negedge seen");
		
		// Burnthrough igniter (leave some cap energy for dump)
		for( int ii = 0; ii < 60*MSEC; ii++ ) @(negedge clk); 
		$display("Igniter Burn Through");
		burn = 1;

		// Should arm drop
		while( !dump ) @(negedge clk); // wait for dump to rise
		$display("Dump Begun");

		// Should seen arm low
		while( arm_led ) @(negedge clk); // wait for arm to drop
		$display("ARM off");

		// final wait
		for( int ii = 0; ii < 10*MSEC; ii++ ) @(negedge clk); 
		$display("Full lanch cycle simulation complate");
		$finish();
	end // fire		
		


	/////////////////////
	// System Model     
	/////////////////////	
	
	parameter R = 2.0; // Load resistance
	parameter R_DUMP = 300.0; // dump resistance f(real is 3k3)
	parameter CAP_VOLTAGE = 320.0;
	parameter COIL_UH = 390.0;
	parameter FREQ_MHZ = 48;
	parameter PERIOD_NS = 20.8;
	parameter CAP_UF = 200.0;  // 200uF
	parameter CH_RATE = 30.0; //  Joule/sec (real 3.0)

	// integer system model for inclusion in fpga
	// to build a chip tester system simulator. 
	// a simulator include an integer model to calaculate
	// the ADC values, which are derived from inductor and capacitor
	// models that respond to control inputs

	logic [11:0] ad_iout, ad_vout, ad_vcap, ad_icap, ad_ecap;

	lcc_syssim #(
    	.ADC_VOLTS_PER_DN	( ADC_VOLTS_PER_DN ), 
		.ADC_DN_PER_AMP		( ADC_DN_PER_AMP   ),
		.ADC_DN_PER_JOULE	( ADC_DN_PER_AMP   ), // joule use amp scale
		.CLOCK_FREQ_MHZ		( CLOCK_FREQ_MHZ   ), 
		.COIL_UH			( COIL_UH ),
		.CAP_UF             ( CAP_UF ),
		.CH_RATE			( CH_RATE ), // normally 2.5 J/s
		.R_DUMP				( R_DUMP ), // normally 3k3
		.R					( R ) // resistance ohms
	) i_intsim (
		.clk	( clk ),
		.reset	( reset ),
		// hardware power control signals
		.dump	( dump ),
		.charge ( charge ),
		.pwm	( pwm ),
		// virtual simulaiton inputs
		.burn	( burn ),
		// ADC outputs
		.ad_iout	( ad_iout ),
		.ad_vout	( ad_vout ),
		.ad_vcap	( ad_vcap ),
		// Monitoring outputs
		.ad_icap	( ad_icap ),
		.ad_ecap	( ad_ecap )
	);

	real m_iout, m_vout, m_vcap, m_icap, m_ecap;
	assign m_iout = ad_iout / ADC_DN_PER_AMP;
	assign m_icap = ad_icap / ADC_DN_PER_AMP;
	assign m_vout = ad_vout * ADC_VOLTS_PER_DN;
	assign m_vcap = ad_vcap * ADC_VOLTS_PER_DN;
	assign m_ecap = ad_ecap / ADC_DN_PER_AMP;

	// Model of power module 
	// root states are capacitor energy and coil (output) current.
	// The model updates these dynamically from the pwm state
	// The cap voltage is derived from cap energy, and cap current from pwm and coil current.
	// The output voltage is a function of igniter resistance and coil (output) current.
	// 


	real ecap, ecap_n; 		
	real icap, icap_n; 
	real vcap, vcap_n; 
	real iout, iout_n; 
	real vout, vout_n; 
	
	initial begin
		// HV Cap model
		vcap = 0.0;
		ecap = 0.0;
		icap = 0.0;
		// HV Coil model
		vout = 0.0; 
		iout = 0.0;

		// on a cycle loop, now responde to power Controls
		forever begin
			@(posedge clk ) ;
			if( dump == 1 ) begin // Dump
				// not output
				iout_n = 0.0;
				vout_n = 0.0;
				// Dump cap into resistor
				icap_n = vcap / R_DUMP;
				ecap_n = ( ecap_n < 0.0 ) ? 0.0 : ecap_n;
				ecap_n = ecap - ((((((icap+icap_n)/2)*vcap) / (FREQ_MHZ*1000000.0)))) ;
				vcap_n = ($sqrt( (2.0 * ecap_n) / CAP_UF ) * 1000.0);
			end else if( charge == 1 ) begin // Charge 
				// not output
				iout_n = 0.0;
				vout_n = 0.0;
				// Dump cap into resistor
				ecap_n = ecap + ( CH_RATE / (FREQ_MHZ*1000000.0) ) ;
				ecap_n = ( ecap_n < 0.0 ) ? 0.0 : ecap_n;
				vcap_n = ($sqrt( (2.0 * ecap_n) / CAP_UF ) * 1000.0);
				icap_n = CH_RATE / vcap_n;
			end else if( burn ) begin // Burn through
				iout_n = 0.0;
				vout_n = vcap;
				icap_n = 0.0;
				vcap_n = vcap;
				ecap_n = ecap;
			end else if( pwm == 0 ) begin // PWM OFF
				// output off, I falls at rate Vout/L*t
				iout_n = iout - ((vout / (COIL_UH * FREQ_MHZ))); 
				// The updated Vout is IR
				vout_n = (iout_n * R);
				// Icap = 0; Ecap, Vcap unchanged
				icap_n = 0;
				vcap_n = vcap;
				ecap_n = ecap;
			end else begin // PWM ON
				// output is on, I rises by (Vin-Vout)/L
				iout_n = iout + (((vcap - vout) / (COIL_UH * FREQ_MHZ)));
				// The updated Vout is IR
				vout_n = (iout_n * R);
				// Icap = Iout
				icap_n = iout_n;
				// cap drops by energy used this cycle IVT
				ecap_n = ecap - ((((((iout+iout_n)/2)*vcap) / (FREQ_MHZ*1000000.0)))) ;
				// votlage is calc from energy
				ecap_n = ( ecap_n < 0.0 ) ? 0.0 : ecap_n;
				vcap_n = ($sqrt( (2.0 * ecap_n) / CAP_UF ) * 1000.0);
			end
			
			// Update to next state
			iout = iout_n;
			vout = vout_n;
			ecap = ecap_n;
			vcap = vcap_n;
			icap = icap_n;		
		end // Analog model
	end // analog model

	
	/////////////////////
	// AD7352 Model     
	/////////////////////
	// Models amplification
	// adc sampling, conversion
	// and transmission
	
	// ADC sampling and transmission.
	logic [11:0] sh_vcap;
	logic [11:0] sh_icap;
	logic [11:0] sh_vout;
	logic [11:0] sh_iout;

	logic n_sclk;
	assign n_sclk = clk; // same clock, adc just uses negedge.
	
	initial begin
		data_n = 4'b0;
	   sh_vcap = 0.0;
		sh_icap = 0.0;
		sh_vout = 0.0;
		sh_iout = 0.0;
		forever begin
			@(negedge n_sclk ) 
			while( n_cs != 1 ) begin // it has to start high
				@(negedge n_sclk ); 
			end
			while( n_cs != 0 ) begin // wait for it to go low
				@(negedge n_sclk ); 
			end
			// first falling edge with n_cs active low, output 2nd zero
			data_n = 4'b0;
			// sample 
			sh_vcap[10:0] = int'(vcap / ADC_VOLTS_PER_DN );
			sh_icap[10:0] = int'(icap * ADC_DN_PER_AMP   );
			sh_vout[10:0] = int'(vout / ADC_VOLTS_PER_DN );
			sh_iout[10:0] = int'(iout * ADC_DN_PER_AMP   );
			sh_vcap[11] = 1;
			sh_icap[11] = 1;
			sh_vout[11] = 1;
			sh_iout[11] = 1;
			@(negedge n_sclk ); 
			@(negedge n_sclk ); 
			for( int bitpos = 11; bitpos >= 0; bitpos-- ) begin
				data_n[3:0] = { sh_vout[bitpos], sh_icap[bitpos], sh_vcap[bitpos], sh_iout[bitpos] }; // { b[1:0], a[1:0] }
				@(negedge n_sclk ); 
			end
			data_n[3:0] = 4'b0;
		end // adc
	end
	
	// adc oe.
	assign data[3:0] = ( n_cs == 1'b0 ) ? data_n[3:0] : 4'bxxxx;
endmodule
