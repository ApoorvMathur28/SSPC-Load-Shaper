`timescale 1ns / 1ps
//======================================================================
// tb_top : clock, DUT + interface, component construction, and the
// constrained-random generator loop (N_TXN transactions).
// Plusargs: +N_TXN=<n> (default 20)  +STRESS (widen past rated range)
//======================================================================
module tb_top;
    logic clk = 0;
    always #10 clk = ~clk;                 // 50 MHz

    sspc_if vif(clk);

    sspc_load_shaper dut (
        .clk(clk), .rst_n(vif.rst_n), .v_bus_adc(vif.v_bus_adc),
        .adc_valid(vif.adc_valid), .payload_req(vif.payload_req),
        .payload_pwm(vif.payload_pwm), .state_o(vif.state_o),
        .fault_latch(vif.fault_latch));

    mailbox #(sspc_txn)    gen2drv = new();
    mailbox #(sspc_txn)    gen2sb  = new();
    mailbox #(sspc_result) drv2sb  = new();
    sspc_driver     drv;
    sspc_scoreboard sb;

    initial begin
        sspc_txn tr;
        int n_txn;
        bit stress;
        if (!$value$plusargs("N_TXN=%d", n_txn)) n_txn = 20;
        stress = $test$plusargs("STRESS");

        drv    = new(vif, gen2drv, drv2sb);
        sb     = new(gen2sb, drv2sb);
        sb.cov = new();

        fork drv.run(); sb.run(); join_none

        repeat (n_txn) begin                 // the generator
            tr = new();
            tr.stress = stress;
            if (!tr.randomize()) $fatal(1, "randomize failed");
            gen2sb.put(tr);
            gen2drv.put(tr);
        end
        while (sb.passes + sb.fails + sb.baseline_runs < n_txn) @(posedge clk);
        sb.report();
        $finish;
    end
endmodule
