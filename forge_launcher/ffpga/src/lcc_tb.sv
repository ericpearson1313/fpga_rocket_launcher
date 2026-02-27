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

        // create reset
        initial begin
        $timeformat(-9, 0, "ns", 12); // 1: scale (ns=-9), 2: decimals, 3: suffix, 4: print-field width
        // configure FST (waveform) dump
        $dumpfile("lcc.fst");
        $dumpvars(1,i_dut);
                reset = 1;
                for( int ii = 0; ii < 10; ii++ ) begin
                        @(negedge clk);
                end
                reset = 0;
                $display("Reset done");
                for( int ii = 0; ii < 50*48000; ii++ ) begin // Max 2000 msec
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

    forge_launcher #( ADC_VOLTS_PER_DN, ADC_DN_PER_AMP, CLOCK_FREQ_MHZ, COIL_IND_UH ) dut (
                // System
                .clk                    ( clk ),
                .reset                  ( reset ), // fpga starts in reset state
                // Front Panel
                .fire_button    		( fire),
                .arm_led                ( arm_led ),
                .cont_led               ( cont_led ),
                .speaker                ( speaker ),
                // High Voltage
                .lt3420_charge          ( charge ),
                .lt3420_done            ( 1'b1 ),
                .pwm            	    ( pwm ),
                .dump                   ( dump ),
                // ADC interface
				.ad_cs					( n_cs ),
				.ad_sdata_a				( data[1:0] ),
				.ad_sdata_b				( data[3:2] ),
                // Tie off Debug inputs
                .iset                   ( { 1'b0, 1'b1, mute } ), // { !autorun, use_est , mute }
                .key                    ( 5'b00000 ),
       			// debug outputs for Display monitoring
       			.ad_a0			( ),
        		.ad_a1			( ),
        		.ad_b0			( ),
        		.ad_b1			( ),
        		.ad_strobe		( ),
        		.iest			( ),
        		.burn			( ),
        		.igniter_res	( ),

        		// Display and Logging control outputs
        		.scroll_halt	( ),
        		.charge			( ),      
        		.fire_done		( ),
        		.fire_button_debounce ( ),
        		.cap_halt		( ),
        		.long_fire		( )
    );
	
	
	// Operating Mode 
		
	initial begin
		// hardware will wait for fire;
		fire = 0;
		mute = 0;
      // startup delay (for future reset)
      for( int ii = 0; ii < 10; ii++ ) @(posedge clk); // 10 cycles
		// Fire
		fire = 1'b1;
	end // fire		
		


	/////////////////////
	// System Model     
	/////////////////////	
	// Model of power module 
	// root states are capacitor energy and coil (output) current.
	// The model updates these dynamically from the pwm state
	// The cap voltage is derived from cap energy, and cap current from pwm and coil current.
	// The output voltage is a function of igniter resistance and coil (output) current.
	// 

	parameter R = 10.0; // Load resistance
	parameter CAP_VOLTAGE = 320.0;
	parameter COIL_UH = 399.0;
	parameter FREQ_MHZ = 48;
	parameter PERIOD_NS = 20.8;
	parameter CAP_UF = 1.0;  // typicall 100uF, but this is faster

	real ecap, ecap_n; 		
	real icap, icap_n; 
	real vcap, vcap_n; 
	real iout, iout_n; 
	real vout, vout_n; 
	
	initial begin
		vcap = CAP_VOLTAGE;
		ecap = (0.5 * CAP_UF * CAP_VOLTAGE * CAP_VOLTAGE)/1000000.0; 
		icap = 0;
		vout = 0;
		iout = 0;

		// on a cycle loop, now responde to PWM 
		// TODO add dump modelling
		
		forever begin
			@(posedge clk ) ;
			if( pwm == 0 ) begin
				// output off, I falls at rate Vout/L*t
				iout_n = iout - ((vout / (COIL_UH * FREQ_MHZ))); 
				// The updated Vout is IR
				vout_n = (iout_n * R);
				// Icap = 0; Ecap, Vcap unchanged
				icap_n = 0;
				vcap_n = vcap;
				ecap_n = ecap;
			end else begin 
				// output is on, I rises by (Vin-Vout)/L
				iout_n = iout + (((vcap - vout) / (COIL_UH * FREQ_MHZ)));
				// The updated Vout is IR
				vout_n = (iout_n * R);
				// Icap = Iout
				icap_n = iout_n;
				// cap drops by energy used this cycle IVT
				ecap_n = ecap - ((((((iout+iout_n)/2)*vcap) / (FREQ_MHZ*1000000.0)))) ;
				// votlage is calc from energy

				vcap_n = ($sqrt( (2.0 * ecap_n) / CAP_UF ) * 1000.0);

			end
			
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
	logic [11:0] sh_vcap;	// 0 to 350 volts  350/4096
	logic [11:0] sh_icap;	// 0 to 12 amp     12/4096
	logic [11:0] sh_vout;	// 0 to 350 volts
	logic [11:0] sh_iout;	// 0 to 12 amp

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
			sh_vcap[11:0] = int'(vcap * 8  );
			sh_icap[11:0] = int'(icap * 256);
			sh_vout[11:0] = int'(vout * 8  );
			sh_iout[11:0] = int'(iout * 256);

			@(negedge n_sclk ); 
			for( int bitpos = 11; bitpos >= 0; bitpos-- ) begin
				data_n[3:0] = { sh_vcap[bitpos], sh_icap[bitpos], sh_vout[bitpos], sh_iout[bitpos] };
				@(negedge n_sclk ); 
			end
			data_n[3:0] = 4'b0;
		end // adc
	end
	
	// adc oe.
	assign data[3:0] = ( n_cs == 1'b0 ) ? data_n[3:0] : 4'bxxxx;
endmodule
