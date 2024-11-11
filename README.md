### fpga_rocket_launcher

# Model Rocket Digital Launch Controller

FPGA based model rocket digital launch controller.

![Assembled and testing](pcb_v0_assy.jpg "Digital Launch Controller Prototype")

Digital constant current capacitive discharge launch controller.

Discharges a 100uF capactor charged to 320V through a 390uH in series with the extension cable and rocket igniter.
Discharg is digitally current controlled with selectable current setting of 1 to 6 Amps.

An analog front end is used to instrument and digitize the capacitor and inductor voltage and current at 3 Mhz 
and control a PWM signal to a Mosfet switching the capacitor discharge. A control loop running at 48 Mhz
models the inductor current and switches off the pwm gate control when the upper limit is reached and on again when the low limit is reached. The model is corrected when new ADC samples arives the difference between the measured and modeled IVs, where the modelled IV values were those at the moment of conversion.

There is alot more to discuss, but here is the schematic

[Schematic](fpga_blaster_schem_v0_8.pdf)



