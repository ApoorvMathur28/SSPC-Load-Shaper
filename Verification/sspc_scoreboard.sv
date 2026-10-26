`timescale 1ns / 1ps
//======================================================================
// sspc_scoreboard : self-checking. A reference model predicts the
// correct outcome from the plant's DC steady state, then each result
// is checked against it.
//
//   V_ss = V_OC - R_PACK * V_OC/(R_PACK + R_SW + R_L)   (steady bus)
//
//   Shaped, V_ss >= V_RECOVER : must reach MONITOR, no fault, and the
//                               bus must never drop below V_CRIT
//   Shaped, V_ss <  V_CRIT    : load exceeds bus capability -> must FAULT
//   Shaped, V_CRIT<=V_ss<V_RECOVER : hysteresis band, flagged as a
//                               known design limit (no watchdog yet)
//   Unprotected               : baseline, recorded (brown-out expected)
//======================================================================
class sspc_scoreboard;
    mailbox #(sspc_txn)    from_gen;
    mailbox #(sspc_result) from_drv;
    sspc_coverage          cov;

    real V_OC = 4.10, R_PACK = 0.30, R_SW = 0.10;
    real V_CRIT = 2745 * (5.0/4096.0);      // 3.351 V
    real V_RECOVER = 2827 * (5.0/4096.0);   // 3.451 V
    int  passes = 0, fails = 0, baseline_brownouts = 0, baseline_runs = 0;

    function new(mailbox #(sspc_txn) from_gen, mailbox #(sspc_result) from_drv);
        this.from_gen = from_gen; this.from_drv = from_drv;
    endfunction

    task run();
        sspc_txn tr; sspc_result res;
        real r_l, v_ss; bit ok; string why;
        forever begin
            from_gen.get(tr);
            from_drv.get(res);
            r_l  = tr.r_l_mohm * 1e-3;
            v_ss = V_OC - R_PACK * V_OC / (R_PACK + R_SW + r_l);
            if (cov != null) cov.sample(tr, res);

            if (!tr.use_shaper) begin
                baseline_runs++;
                if (res.vmin < V_CRIT) baseline_brownouts++;
                $display("[BASE] %s -> vmin=%.3f V (%s)", tr.convert2str(), res.vmin,
                         (res.vmin < V_CRIT) ? "brown-out" : "no brown-out");
                continue;
            end

            if (v_ss < V_CRIT) begin
                ok  = res.fault;
                why = "overload: expected FAULT";
            end else if (v_ss < V_RECOVER) begin
                ok  = 1'b0;
                why = "steady bus inside hysteresis band: FSM cannot reach MONITOR";
            end else begin
                ok  = (res.state == 2'b01) && !res.fault && (res.vmin >= V_CRIT);
                why = "expected MONITOR, no fault, vmin >= 3.35 V";
            end

            if (ok) begin
                passes++;
                $display("[PASS] %s -> vmin=%.3f V state=%0d fault=%0d", tr.convert2str(),
                         res.vmin, res.state, res.fault);
            end else begin
                fails++;
                $display("[FAIL] %s -> vmin=%.3f V state=%0d fault=%0d (%s)", tr.convert2str(),
                         res.vmin, res.state, res.fault, why);
            end
        end
    endtask

    function void report();
        $display("==== BASELINE: %0d of %0d unprotected turn-ons browned out ====",
                 baseline_brownouts, baseline_runs);
        $display("==== SCOREBOARD: %0d passed, %0d failed ====", passes, fails);
        if (cov != null) cov.report();
    endfunction
endclass
