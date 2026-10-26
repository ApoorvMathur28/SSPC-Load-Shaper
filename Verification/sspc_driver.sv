`timescale 1ns / 1ps
//======================================================================
// sspc_driver : applies one transaction to the DUT and runs the bus +
// payload plant model alongside it, one integration step per clock.
//
//   battery V_OC behind R_PACK -> bus (C_BUS) -> switch R_SW -> payload
//   payload = input capacitor C_PL (starts empty) || steady load R_L
//
// Sends an sspc_result record (defined in sspc_txn.sv) to the
// scoreboard. The model is a lumped behavioral model, not SPICE.
//======================================================================
class sspc_driver;
    virtual sspc_if vif;
    mailbox #(sspc_txn)    in_mbx;
    mailbox #(sspc_result) out_mbx;

    real V_OC = 4.10, R_PACK = 0.30, C_BUS = 47e-6, R_SW = 0.10;
    real ADC_LSB = 5.0/4096.0, DT = 20e-9;
    int  WIN_CLKS = 1_150_000;          // 23 ms: covers the ~20.7 ms ramp

    function new(virtual sspc_if vif, mailbox #(sspc_txn) in_mbx,
                 mailbox #(sspc_result) out_mbx);
        this.vif = vif; this.in_mbx = in_mbx; this.out_mbx = out_mbx;
    endfunction

    task run();
        sspc_txn tr;
        forever begin
            in_mbx.get(tr);
            drive_one(tr);
        end
    endtask

    task drive_one(sspc_txn tr);
        real vb, vp, i_src, i_sw, c_pl, r_l, vmin;
        bit  sw_on;
        sspc_result res = new();
        c_pl = tr.c_pl_uf  * 1e-6;
        r_l  = tr.r_l_mohm * 1e-3;
        vb = V_OC; vp = 0.0; vmin = V_OC;

        // reset DUT, bus idle at V_OC
        vif.cb.rst_n       <= 1'b0;
        vif.cb.payload_req <= 1'b0;
        vif.cb.adc_valid   <= 1'b0;
        vif.cb.v_bus_adc   <= 12'($rtoi(V_OC / ADC_LSB));
        repeat (10) @(vif.cb);
        vif.cb.rst_n <= 1'b1;
        repeat (200) @(vif.cb);

        vif.cb.payload_req <= 1'b1;                     // turn-on event
        for (int n = 1; n <= WIN_CLKS; n++) begin
            @(vif.cb);
            sw_on = tr.use_shaper ? vif.cb.payload_pwm : 1'b1;
            i_src = (V_OC - vb) / R_PACK;
            i_sw  = (sw_on && vb > vp) ? (vb - vp) / R_SW : 0.0;
            vb    = vb + (i_src - i_sw) * DT / C_BUS;
            vp    = vp + (i_sw - vp / r_l) * DT / c_pl;
            if (vb < vmin) vmin = vb;
            if (n % 10 == 0) begin                      // 5 MSPS ADC
                vif.cb.v_bus_adc <= 12'($rtoi(vb / ADC_LSB));
                vif.cb.adc_valid <= 1'b1;
            end else
                vif.cb.adc_valid <= 1'b0;
        end
        @(vif.cb);
        res.vmin  = vmin;
        res.v_pl  = vp;
        res.state = vif.cb.state_o;
        res.fault = vif.cb.fault_latch;
        vif.cb.payload_req <= 1'b0;
        repeat (10) @(vif.cb);
        out_mbx.put(res);
    endtask
endclass
