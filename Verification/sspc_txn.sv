//======================================================================
// sspc_txn : one stimulus item. Randomized so the simulator generates
// many different turn-on scenarios automatically (constrained-random).
`timescale 1ns / 1ps
class sspc_txn;
    // rand = simulator picks a random value each randomize() call
    rand int unsigned inrush_mA;    // payload inrush current, milliamps
    rand int unsigned delay_clks;   // delay before asserting payload_req
    rand bit          use_shaper;   // 1 = shaped path, 0 = unprotected

    // Constraints keep the random values physically sensible
    constraint c_inrush { inrush_mA inside {[1000:2500]}; }   // 1..4 A
    constraint c_delay  { delay_clks inside {[10:200]}; }

    // A print helper so logs are readable
    function string convert2str();
        return $sformatf("inrush=%0d mA, delay=%0d, shaper=%0d",
                         inrush_mA, delay_clks, use_shaper);
    endfunction
endclass