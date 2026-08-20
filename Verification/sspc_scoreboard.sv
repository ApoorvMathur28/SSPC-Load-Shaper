`timescale 1ns / 1ps
//======================================================================
// sspc_scoreboard : self-checking comparison + coverage sampling.
//======================================================================
class sspc_scoreboard;
    mailbox #(real)     from_drv;
    mailbox #(sspc_txn) from_gen;
    sspc_coverage       cov;

    real THRESH = 3.35;
    int  passes = 0, fails = 0;

    function new(mailbox#(real) from_drv, mailbox#(sspc_txn) from_gen);
        this.from_drv = from_drv; this.from_gen = from_gen;
    endfunction

    task run();
        sspc_txn tr; real vmin; bit ok;
        forever begin
            from_gen.get(tr);
            from_drv.get(vmin);
            if (tr.use_shaper) ok = (vmin >= THRESH);
            else               ok = 1;
            if (cov != null) cov.sample(tr.inrush_mA, vmin, tr.use_shaper);
            if (ok) begin
                passes++;
                $display("[PASS] %s -> vmin=%.3f V", tr.convert2str(), vmin);
            end else begin
                fails++;
                $display("[FAIL] %s -> vmin=%.3f V (below %.2f V)",
                         tr.convert2str(), vmin, THRESH);
            end
        end
    endtask

    function void report();
        $display("==== SCOREBOARD: %0d passed, %0d failed ====", passes, fails);
        if (cov != null) cov.report();
    endfunction
endclass