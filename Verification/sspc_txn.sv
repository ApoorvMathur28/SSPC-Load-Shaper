`timescale 1ns / 1ps
//======================================================================
// sspc_txn : one randomized payload turn-on scenario.
//   c_pl_uf   : payload input capacitance (uF)   -> sets inrush energy
//   r_l_mohm  : payload steady load (milliohm)   -> sets running current
//   use_shaper: 1 = switch driven by SSPC PWM, 0 = direct (baseline)
// Rated range constraints by default; +STRESS widens them past the
// rated envelope so the scoreboard can find the operating limits.
//======================================================================
class sspc_txn;
    rand int unsigned c_pl_uf;
    rand int unsigned r_l_mohm;
    rand bit          use_shaper;
    bit               stress;          // set by the generator, not randomized

    constraint c_rated  { (stress == 0) -> c_pl_uf  inside {[47:1000]};
                          (stress == 0) -> r_l_mohm inside {[2000:10000]}; }
    constraint c_stress {  stress -> c_pl_uf  inside {[47:4700]};
                           stress -> r_l_mohm inside {[1000:10000]}; }

    function string convert2str();
        return $sformatf("C_PL=%0d uF, R_L=%0d mOhm, shaper=%0d",
                         c_pl_uf, r_l_mohm, use_shaper);
    endfunction
endclass

//======================================================================
// sspc_result : what the driver observed for one transaction.
// Declared here so every later file (coverage, driver, scoreboard) sees it.
//======================================================================
class sspc_result;
    real    vmin;        // lowest bus voltage after turn-on (V)
    real    v_pl;        // payload voltage at end of window (V)
    bit [1:0] state;     // FSM state at end of window
    bit     fault;       // fault_latch at end of window
endclass
