import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles
from cocotb.triggers import RisingEdge
from cocotb.triggers import FallingEdge
from cocotb.triggers import ReadOnly, Timer

import os
import glob
import itertools
from PIL import Image, ImageChops


@cocotb.test()
async def test_project(dut):
    # cocotb.pass_test()
    # Set clock period to 20 ns (50 MHz)
    CLOCK_PERIOD = 20
    clock = Clock(dut.clk, CLOCK_PERIOD, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset the design
    dut.ena.value = 1
    dut.ui_in.value = 3 #bits 0,1 are active low
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

    # charge should rise after reset
    cocotb.log.info("Charge = %s", dut.uo_out.value[3] )
    while dut.uo_out.value[3] != 1:
        await FallingEdge( dut.clk )
    cocotb.log.info("Charge started")
    cocotb.log.info("Charge = %s", dut.uo_out.value[3] )

    # wait for charge to complete and arm led high
    while dut.uo_out.value[3] == 1:
        await FallingEdge( dut.clk )
    cocotb.log.info("Charge done, arm_led %s", dut.uo_out.value[0] )

    await Timer(1, unit="ms")
    cocotb.log.info("1ms exit")
    cocotb.pass_test() # FINISH

    # wait for speaker tone
    await RisingEdge(dut.uo_out.value[2] )
    cocotb.log.info("ontinuity tone, cont_led %s", dut.uo_out.value[1] );

    # wait 50ms and assert /launch button
    await Timer(50, unit="ms")
    cocotb.log.info("Press Button")
    dut.ui_in.value[0] = 0

    # wait 6ms for debounce and de-assert launch
    await Timer(50, unit="ms")
    cocotb.log.info("Release Button");
    dut.ui_in.value[0] = 1

    # should see pwm on/off
    await RisingEdge(dut.uo_out.value[4] )
    cocotb.log.info("PWM posedge seen")
    await FallingEdge(dut.uo_out.value[4] )
    cocotb.log.info("PWM negedge seen")

    # wait some time and then assert burn through
    await Timer(50, unit="ms")
    cocotb.log.info("gniter Burn Through")
    dut.ui_in.value[7] = 1

    # wait for dump to rise (1.3sec)
    await RisingEdge(dut.uo_out.value[5])
    cocotb.log.info("Dump Begin");

    # wait to see arm low 
    await FallingEdge(dut.uo_out.value[0])
    cocotb.log.info("Arm Off");

    # if we reach here it works
    cocotb.log.info("Full lanch cycle simulation complate");
    cocotb.pass_test()

@cocotb.test()
async def compare_reference(dut):
    cocotb.pass_test()
