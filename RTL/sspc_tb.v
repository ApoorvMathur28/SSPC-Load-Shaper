`timescale 1ns / 1ps
//======================================================================
// tb_sspc : plant model + brownout comparison (shaped vs unshaped)
// Cleaned sequencing: full plant reset + vmin arming per run.
//======================================================================
module tb_sspc;
    reg  clk = 0, rst_n = 0, payload_req = 0;
    reg  [11:0] v_bus_adc = 12'd4095;
    reg  adc_valid = 0;
    reg  bypass = 0;
    wire payload_pwm;
    wire [1:0] state_o;
    wire fault_latch;

    wire load_on = bypass ? payload_req : payload_pwm;

    sspc_load_shaper dut (
        .clk(clk), .rst_n(rst_n), .v_bus_adc(v_bus_adc),
        .adc_valid(adc_valid), .payload_req(payload_req),
        .payload_pwm(payload_pwm), .state_o(state_o), .fault_latch(fault_latch)
    );

    always #10 clk = ~clk;   // 50 MHz

    // ---- Plant parameters ----
    real V_OC   = 4.10;
    real R_PACK = 0.30;
    real C_BUS  = 47e-6;
    real I_PEAK = 3.5;
    real ADC_LSB = 5.0/4096.0;
    real DT     = 200e-9;

    // ---- Plant state ----
    real v_bus, q_cap, i_load, i_src, vmin;
    reg  plant_run = 0;      // gate: plant only integrates when armed
    reg  track     = 0;      // gate: only capture vmin when tracking

    // Plant integrator
    always begin
        #200;
        if (plant_run) begin
            i_load = load_on ? I_PEAK : 0.0;
            i_src  = (V_OC - v_bus) / R_PACK;
            q_cap  = q_cap + (i_src - i_load) * DT;
            if (q_cap < 0.0) q_cap = 0.0;
            v_bus  = q_cap / C_BUS;
            if (v_bus > V_OC) v_bus = V_OC;
            if (track && (v_bus < vmin)) vmin = v_bus;
            v_bus_adc = $rtoi(v_bus / ADC_LSB);
            @(posedge clk) adc_valid = 1'b1;
            @(posedge clk) adc_valid = 1'b0;
        end
    end

    // ---- Task: run one turn-on and report ----
    task run_case(input is_bypass, input [200:0] label);
        begin
            // full reset of plant + DUT
            plant_run = 0; track = 0; payload_req = 0;
            rst_n = 0;
            v_bus = V_OC; q_cap = V_OC*C_BUS; vmin = V_OC;
            v_bus_adc = $rtoi(V_OC/ADC_LSB);
            bypass = is_bypass;
            #200; rst_n = 1;
            plant_run = 1;          // start integrating (bus idle, holds at V_OC)
            #4000;                  // let it settle at V_OC
            track = 1;              // arm vmin capture
            payload_req = 1;        // <-- the turn-on event
            #250000;                // observe the whole transient + ramp
            payload_req = 0;
            #4000;
            $display("%0s min bus = %f V", label, vmin);
            plant_run = 0;
        end
    endtask

    initial begin
        #100;
        run_case(1'b1, "UNPROTECTED");   // direct connect, no shaping
        run_case(1'b0, "SHAPED     ");   // shaper active
        $finish;
    end

    initial begin
        $dumpfile("sspc.vcd");
        $dumpvars(0, tb_sspc);
    end
endmodule