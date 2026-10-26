`timescale 1ns / 1ps
//======================================================================
// sspc_if : bundles the DUT signals; clocking block sets drive/sample
// timing relative to the clock edge (avoids testbench/DUT races).
//======================================================================
interface sspc_if (input logic clk);
    logic        rst_n;
    logic [11:0] v_bus_adc;
    logic        adc_valid;
    logic        payload_req;
    logic        payload_pwm;
    logic [1:0]  state_o;
    logic        fault_latch;

    clocking cb @(posedge clk);
        default input #1step output #1;
        output rst_n, v_bus_adc, adc_valid, payload_req;   // TB drives
        input  payload_pwm, state_o, fault_latch;           // TB samples
    endclocking
endinterface
