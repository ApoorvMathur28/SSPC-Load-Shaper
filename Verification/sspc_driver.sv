//======================================================================
// sspc_driver : takes transactions from a mailbox and applies them to
// the DUT through the interface, running the bus plant model alongside.
`timescale 1ns / 1ps
class sspc_driver;
    virtual sspc_if vif;          // handle to the interface
    mailbox #(sspc_txn) mbx;      // incoming transactions
    mailbox #(real)     to_sb;    // send the achieved min-bus to scoreboard

    // plant state
    real V_OC = 4.10, R_PACK = 0.30, C_BUS = 47e-6;
    real ADC_LSB = 5.0/4096.0;
    real v_bus, q_cap, vmin;

    function new(virtual sspc_if vif, mailbox#(sspc_txn) mbx, mailbox#(real) to_sb);
        this.vif = vif; this.mbx = mbx; this.to_sb = to_sb;
    endfunction

    task run();
        sspc_txn tr;
        forever begin
            mbx.get(tr);                 // wait for a transaction
            reset_plant();
            drive_one(tr);
            to_sb.put(vmin);             // report achieved minimum
        end
    endtask

    task reset_plant();
        v_bus = V_OC; q_cap = V_OC*C_BUS; vmin = V_OC;
        vif.rst_n = 0; vif.payload_req = 0; vif.adc_valid = 0;
        vif.v_bus_adc = $rtoi(V_OC/ADC_LSB);
        repeat (4) @(vif.cb);
        vif.rst_n = 1;
    endtask

    task drive_one(sspc_txn tr);
        real i_load, i_src, i_peak;
        int  cyc;
        i_peak = tr.inrush_mA / 1000.0;
        repeat (tr.delay_clks) @(vif.cb);
        vif.payload_req <= 1;
        // run the plant for a fixed observation window
        for (cyc = 0; cyc < 20000; cyc++) begin
            // load current: shaped -> gated by payload_pwm; else direct
            if (tr.use_shaper) i_load = vif.payload_pwm ? i_peak : 0.0;
            else               i_load = i_peak;
            i_src = (V_OC - v_bus) / R_PACK;
            q_cap = q_cap + (i_src - i_load) * 200e-9;
            if (q_cap < 0) q_cap = 0;
            v_bus = q_cap / C_BUS;
            if (v_bus > V_OC) v_bus = V_OC;
            if (v_bus < vmin) vmin = v_bus;
            vif.v_bus_adc <= $rtoi(v_bus/ADC_LSB);
            @(vif.cb) vif.adc_valid <= 1;
            @(vif.cb) vif.adc_valid <= 0;
        end
        vif.payload_req <= 0;
    endtask
endclass