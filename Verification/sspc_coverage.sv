`timescale 1ns / 1ps
//======================================================================
// sspc_coverage : records which scenarios were actually exercised.
// vmin is sampled as an integer (centivolts) to keep xsim happy.
//======================================================================
class sspc_coverage;
    int unsigned inrush_mA;
    int          vmin_cv;      // vmin in centivolts (e.g. 3.475 V -> 347)
    bit          use_shaper;

    covergroup cg;
        cp_inrush: coverpoint inrush_mA {
            bins low  = {[1000:1500]};
            bins mid  = {[1501:2100]};
            bins high = {[2101:2500]};
        }
        cp_shaper: coverpoint use_shaper {
            bins shaped      = {1};
            bins unprotected = {0};
        }
        cp_margin: coverpoint vmin_cv {
            bins comfortable = {[350:410]};
            bins near_line   = {[335:349]};
            bins brownout    = {[300:334]};
        }
        x_stress: cross cp_inrush, cp_shaper;
    endgroup

    function new(); cg = new(); endfunction

    function void sample(int unsigned ir, real vm, bit sh);
        inrush_mA  = ir;
        vmin_cv    = int'(vm * 100.0);
        use_shaper = sh;
        cg.sample();
    endfunction

    function void report();
        $display("==== COVERAGE: %.1f%% ====", cg.get_coverage());
    endfunction
endclass