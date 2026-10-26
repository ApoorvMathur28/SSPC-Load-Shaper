`timescale 1ns / 1ps
//======================================================================
// sspc_coverage : records which scenarios were actually exercised.
// vmin is sampled in integer centivolts (3.475 V -> 347) because
// xsim handles integer coverpoints more reliably than real ones.
// Note: small/medium/large are Verilog keywords (charge strengths), so
// bin names are prefixed.
//======================================================================
class sspc_coverage;
    int unsigned c_pl_uf, r_l_mohm, vmin_cv;
    bit          use_shaper;
    bit [1:0]    state;

    covergroup cg;
        cp_cap: coverpoint c_pl_uf {
            bins cap_small  = {[47:150]};
            bins cap_mid    = {[151:470]};
            bins cap_large  = {[471:1000]};
        }
        cp_load: coverpoint r_l_mohm {
            bins load_heavy = {[2000:2999]};
            bins load_mid   = {[3000:5999]};
            bins load_light = {[6000:10000]};
        }
        cp_shaper: coverpoint use_shaper {
            bins shaped      = {1};
            bins unprotected = {0};
        }
        cp_margin: coverpoint vmin_cv {
            bins comfortable = {[380:410]};
            bins adequate    = {[350:379]};
            bins near_line   = {[335:349]};
            bins brownout    = {[0:334]};
        }
        cp_outcome: coverpoint state {
            bins monitor = {2'b01};
            bins shape   = {2'b10};
            bins fault   = {2'b11};
        }
        x_cap_shaper:  cross cp_cap,  cp_shaper;
        x_load_shaper: cross cp_load, cp_shaper;
    endgroup

    function new(); cg = new(); endfunction

    function void sample(sspc_txn tr, sspc_result res);
        c_pl_uf    = tr.c_pl_uf;
        r_l_mohm   = tr.r_l_mohm;
        use_shaper = tr.use_shaper;
        vmin_cv    = (res.vmin < 0.0) ? 0 : int'(res.vmin * 100.0);
        state      = res.state;
        cg.sample();
    endfunction

    function void report();
        $display("==== COVERAGE: %.1f%% ====", cg.get_coverage());
    endfunction
endclass
