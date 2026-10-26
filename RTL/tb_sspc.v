`timescale 1ns / 1ps
//======================================================================
// tb_sspc : directed testbench with a physical bus + payload plant.
//
// Plant (integrated every 20 ns clock):
//   battery  V_OC behind R_PACK  -> bus node, bulk cap C_BUS
//   switch   R_SW, closed when sw_on                -> payload node
//   payload  input capacitor C_PL (starts EMPTY) || steady load R_L
//
//   i_src = (V_OC - v_bus)/R_PACK
//   i_sw  = sw_on ? (v_bus - v_pl)/R_SW : 0
//   v_bus += (i_src - i_sw)*dt/C_BUS
//   v_pl  += (i_sw - v_pl/R_L)*dt/C_PL
//
// Runs the same turn-on twice: UNPROTECTED (switch follows payload_req
// directly) and SHAPED (switch driven by the SSPC's payload_pwm).
// Plusargs: +CPL=<F> +RL=<ohm> +WIN=<ns> +CSV=1 (dumps 1-us samples)
//======================================================================
module tb_sspc;
    reg  clk = 0, rst_n = 0, payload_req = 0, adc_valid = 0, bypass = 0;
    reg  [11:0] v_bus_adc = 12'd4095;
    wire payload_pwm, fault_latch;
    wire [1:0] state_o;
    wire sw_on = bypass ? payload_req : payload_pwm;

    sspc_load_shaper dut (
        .clk(clk), .rst_n(rst_n), .v_bus_adc(v_bus_adc), .adc_valid(adc_valid),
        .payload_req(payload_req), .payload_pwm(payload_pwm),
        .state_o(state_o), .fault_latch(fault_latch));

    always #10 clk = ~clk;                       // 50 MHz

    // ---- Plant parameters ----
    real V_OC = 4.10, R_PACK = 0.30, C_BUS = 47e-6, R_SW = 0.10;
    real C_PL = 220e-6, R_L = 4.0;
    real ADC_LSB = 5.0/4096.0, DT = 20e-9;

    // ---- Plant state / measurements ----
    real    vb, vp, i_src, i_sw, vmin, ipk, i_acc;
    reg     run = 0, track = 0;
    integer n = 0, WIN, CSV = 0, fd = 0, t_mon;

    always @(posedge clk) if (run) begin
        i_src = (V_OC - vb) / R_PACK;
        i_sw  = (sw_on && vb > vp) ? (vb - vp) / R_SW : 0.0;
        vb    = vb + (i_src - i_sw) * DT / C_BUS;
        vp    = vp + (i_sw - vp / R_L) * DT / C_PL;
        if (track && vb < vmin)  vmin = vb;
        if (track && i_sw > ipk) ipk  = i_sw;
        if (track && t_mon < 0 && state_o == 2'b01) t_mon = n;
        i_acc = i_acc + i_src;
        n = n + 1;
        // ADC: new sample every 10 clocks (5 MSPS)
        if (n % 10 == 0) begin v_bus_adc <= $rtoi(vb / ADC_LSB); adc_valid <= 1'b1; end
        else adc_valid <= 1'b0;
        if (CSV && track && (n % 50 == 0)) begin  // 1-us samples, battery current averaged
            $fdisplay(fd, "%0d,%0d,%f,%f,%f,%0d,%0d", bypass, n/50, vb, vp, i_acc/50.0, dut.duty_q, state_o);
            i_acc = 0;
        end else if (n % 50 == 0) i_acc = 0;
    end

    task run_case(input is_bypass, input [8*12-1:0] label);
        begin
            run = 0; track = 0; payload_req = 0; rst_n = 0; bypass = is_bypass;
            vb = V_OC; vp = 0.0; vmin = V_OC; ipk = 0.0; i_acc = 0; n = 0; t_mon = -1;
            v_bus_adc = $rtoi(V_OC / ADC_LSB);
            #200 rst_n = 1; run = 1;
            #4000;                                 // settle at V_OC
            n = 0; track = 1; payload_req = 1;     // the turn-on event
            #(WIN);
            $display("%0s min bus = %f V | final bus = %f V | payload = %f V | peak i_sw = %f A | state = %0d | fault = %0d | t_monitor = %0.2f ms",
                     label, vmin, vb, vp, ipk, state_o, fault_latch,
                     (t_mon < 0) ? -1.0 : t_mon * 20e-6);
            payload_req = 0; #4000; run = 0;
        end
    endtask

    initial begin
        if (!$value$plusargs("WIN=%d", WIN)) WIN = 25_000_000;    // 25 ms
        if ($value$plusargs("CPL=%f", C_PL)) ;
        if ($value$plusargs("RL=%f",  R_L))  ;
        if ($value$plusargs("CSV=%d", CSV) && CSV) begin
            fd = $fopen("sspc_wave.csv", "w");
            $fdisplay(fd, "bypass,t_us,v_bus,v_payload,i_batt,duty,state");
        end
        #100;
        run_case(1'b1, "UNPROTECTED");
        run_case(1'b0, "SHAPED     ");
        if (fd) $fclose(fd);
        $finish;
    end
endmodule
