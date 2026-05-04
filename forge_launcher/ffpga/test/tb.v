`default_nettype none
`timescale 1ns / 1ps
// vim: ts=4:

/* This testbench just instantiates the module and makes some convenient wires
   that can be driven / tested by the cocotb test.py.
*/
module tb ();

  // Dump the signals to a FST file. You can view it with gtkwave or surfer.
  initial begin
    $dumpfile("tb.fst");
    $dumpvars(0, tb);
    #1;
  end

  // Wire up the inputs and outputs:
  reg clk;
  reg rst_n;
  reg ena;
  reg [7:0] ui_in;
  reg [7:0] uio_in;
  wire [7:0] uo_out;
  wire [7:0] uio_out;
  wire [7:0] uio_oe;
`ifdef GL_TEST
  wire VPWR = 1'b1;
  wire VGND = 1'b0;
`endif

  // sim test signals fed into DUT
  logic [4:2] sys_sim; // in lieu of ui_in[4:2]

  // Replace tt_um_example with your module name:
  tt_um_eric_lcc user_project (

      // Include power ports for the Gate Level test:
`ifdef GL_TEST
      .VPWR(VPWR),
      .VGND(VGND),
`endif

      .ui_in  ({ui_in[7:5], sys_sim[4:2], ui_in[1:0]} ),    // Dedicated inputs
      .uo_out (uo_out),   // Dedicated outputs
      .uio_in (uio_in),   // IOs: Input path
      .uio_out(uio_out),  // IOs: Output path
      .uio_oe (uio_oe),   // IOs: Enable path (active high: 0=input, 1=output)
      .ena    (ena),      // enable - goes high when design is selected
      .clk    (clk),      // clock
      .rst_n  (rst_n)     // not reset
  );

 // add the integer system model used on test stand fpga
 // scale down R,C and increate the charge rate to shorted sim
 // syssim monitors the dut outputs, and gives the adc system response

     lcc_syssim #(
        .ADC_VOLTS_PER_DN   ( 0.2005 ),
        .ADC_DN_PER_AMP     ( 205 ),
        .ADC_DN_PER_JOULE   ( 205 ), 
        .CLOCK_FREQ_MHZ     ( 48 ),
        .COIL_UH            ( 390.0 ),
        .CAP_UF             ( 2.0 ), // normally 200.0, 
        .CH_RATE            ( 50 ), // normally 2.5 J/s
        .R_DUMP             ( 30 ), // normally 3k3
        .R                  ( 3 ) // resistance ohms
    ) i_intsim (
        .clk    ( clk ),
        .reset  ( !rst_n ),
        // hardware power control signals
        .charge ( uo_out[3] ),
        .pwm    ( uo_out[4] ),
        .dump   ( uo_out[5] ),
        // virtual simulaiton inputs
        .burn   ( ui_in[7] ), // sim control not used by hardware
        // ADC outputs
        .ad_iout    ( sys_sim[2] ), 
        .ad_vout    ( sys_sim[3] ),
        .ad_vcap    ( sys_sim[4] ),
        // Monitoring outputs
        .ad_icap    ( ),
        .ad_ecap    ( )
    );

endmodule
