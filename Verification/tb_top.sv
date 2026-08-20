`timescale 1ns / 1ps
module tb_top;
    logic clk = 0;
    always #10 clk = ~clk;

    sspc_if vif(clk);

    sspc_load_shaper dut (
        .clk(clk), .rst_n(vif.rst_n), .v_bus_adc(vif.v_bus_adc),
        .adc_valid(vif.adc_valid), .payload_req(vif.payload_req),
        .payload_pwm(vif.payload_pwm), .state_o(vif.state_o),
        .fault_latch(vif.fault_latch)
    );

    mailbox #(sspc_txn) gen2drv = new();
    mailbox #(sspc_txn) gen2sb  = new();
    mailbox #(real)     drv2sb  = new();
    sspc_driver     drv;
    sspc_scoreboard sb;

    initial begin
        sspc_txn tr;
        drv = new(vif, gen2drv, drv2sb);
        sb  = new(drv2sb, gen2sb);
        sb.cov = new();

        fork drv.run(); sb.run(); join_none

        repeat (20) begin
            tr = new();
            assert(tr.randomize());
            gen2drv.put(tr);
            gen2sb.put(tr);
            wait (gen2drv.num() == 0);
            repeat (100) @(posedge clk);
        end
        #5000;
        sb.report();
        $finish;
    end
endmodule