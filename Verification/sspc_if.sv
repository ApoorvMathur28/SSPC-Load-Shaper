//======================================================================
// sspc_if : interface bundling all DUT signals + a clocking block.
// Every testbench component talks to the DUT through this, never
// directly to the wires. This is the UVM-style wires/testbench split.
`timescale 1ns / 1ps
interface sspc_if (input logic clk);
    // --- DUT signals ---
    logic        rst_n;
    logic [11:0] v_bus_adc;
    logic        adc_valid;
    logic        payload_req;
    logic        payload_pwm;
    logic [1:0]  state_o;
    logic        fault_latch;

    // --- Clocking block: defines WHEN the testbench drives/samples ---
    // 'default input #1step output #1' = sample just before the edge,
    // drive just after it. This avoids testbench-vs-DUT races.
    clocking cb @(posedge clk);
        default input #1step output #1;
        output rst_n, v_bus_adc, adc_valid, payload_req;  // TB drives these
        input  payload_pwm, state_o, fault_latch;          // TB samples these
    endclocking

    // A modport groups signals by direction for a given user.
    // The testbench uses the clocking block; the DUT sees raw wires.
    modport TB (clocking cb, output rst_n);
endinterface 