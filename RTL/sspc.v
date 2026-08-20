`timescale 1ns / 1ps
//======================================================================
// sspc_load_shaper : RTL load shaper for CubeSat EPS
// FSM-driven adaptive PWM soft-start to limit payload inrush current
// and prevent bus brown-out. Functional-simulation configuration.
//======================================================================
module sspc_load_shaper #(
    parameter integer ADC_W         = 12,
    parameter integer PWM_W         = 8,
    parameter integer RAMP_W        = 8,          // small so sim runs fast
    parameter [ADC_W-1:0] THRESH_CRIT    = 12'd2745,  // ~3.35 V fault line
    parameter [ADC_W-1:0] THRESH_DVDT    = 12'd41,    // ~50 mV/sample slope
    parameter [ADC_W-1:0] THRESH_RECOVER = 12'd2827,  // ~3.45 V recovery (hysteresis)
    parameter [PWM_W-1:0] DUTY_START     = 8'd8,
    parameter [PWM_W-1:0] DUTY_STEP      = 8'd3,
    parameter [PWM_W-1:0] DUTY_MAX       = 8'd255
)(
    input  wire              clk,
    input  wire              rst_n,
    input  wire [ADC_W-1:0]  v_bus_adc,
    input  wire              adc_valid,   // 1-clk strobe: new ADC sample
    input  wire              payload_req,
    output reg               payload_pwm,
    output wire [1:0]        state_o,
    output reg               fault_latch
);
    localparam [1:0] S_OFF=2'b00, S_MONITOR=2'b01, S_SHAPE=2'b10, S_FAULT=2'b11;
    reg [1:0] state_q, state_d;
    assign state_o = state_q;

    // ---- ADC sample capture + dV/dt on consecutive SAMPLES (not clocks) ----
    reg [ADC_W-1:0] v_prev;
    reg             dvdt_trip_q, v_crit_q, v_recov_q;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v_prev <= 0; dvdt_trip_q <= 0; v_crit_q <= 0; v_recov_q <= 0;
        end else if (adc_valid) begin
            v_prev      <= v_bus_adc;
            dvdt_trip_q <= (v_prev > v_bus_adc) && ((v_prev - v_bus_adc) >= THRESH_DVDT);
            v_crit_q    <= (v_bus_adc <= THRESH_CRIT);
            v_recov_q   <= (v_bus_adc >= THRESH_RECOVER);
        end else if (state_q == S_SHAPE || state_q == S_FAULT) begin
            dvdt_trip_q <= 1'b0;   // consumed
        end
    end

    // ---- PWM counter + saturating duty ramp ----
    reg [PWM_W-1:0]  pwm_cnt, duty_q;
    reg [RAMP_W-1:0] ramp_cnt;
    wire ramp_tick   = (ramp_cnt == {RAMP_W{1'b1}});
    wire ramp_done   = (duty_q == DUTY_MAX);
    wire enter_shape = (state_q != S_SHAPE) && (state_d == S_SHAPE);

    always @(posedge clk or negedge rst_n)
        if (!rst_n) pwm_cnt <= 0; else pwm_cnt <= pwm_cnt + 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            duty_q <= 0; ramp_cnt <= 0;
        end else if (enter_shape) begin
            duty_q <= DUTY_START; ramp_cnt <= 0;          // critical init fix
        end else if (state_q == S_SHAPE) begin
            ramp_cnt <= ramp_cnt + 1'b1;
            if (ramp_tick && !ramp_done)
                duty_q <= (duty_q > (DUTY_MAX - DUTY_STEP)) // saturating add
                          ? DUTY_MAX : duty_q + DUTY_STEP;
        end else if (state_q == S_MONITOR) begin
            duty_q <= DUTY_MAX; ramp_cnt <= 0;
        end else begin
            duty_q <= 0; ramp_cnt <= 0;
        end
    end

    // ---- Next-state logic ----
    always @(*) begin
        state_d = state_q;
        case (state_q)
            S_OFF:     if (payload_req) state_d = S_SHAPE;        // always soft-start
            S_MONITOR: if (!payload_req)      state_d = S_OFF;
                       else if (v_crit_q)     state_d = S_FAULT;
                       else if (dvdt_trip_q)  state_d = S_SHAPE;
            S_SHAPE:   if (!payload_req)                    state_d = S_OFF;
                       else if (v_crit_q)                  state_d = S_FAULT;
                       else if (ramp_done && v_recov_q)    state_d = S_MONITOR; // hysteresis
            S_FAULT:   if (!payload_req) state_d = S_OFF;
            default:   state_d = S_OFF;
        endcase
    end

    always @(posedge clk or negedge rst_n)
        if (!rst_n) state_q <= S_OFF; else state_q <= state_d;

    // ---- Fault telemetry latch ----
    always @(posedge clk or negedge rst_n)
        if (!rst_n)                  fault_latch <= 1'b0;
        else if (state_q == S_FAULT) fault_latch <= 1'b1;
        else if (!payload_req)       fault_latch <= 1'b0;

    // ---- Output ----
    always @(*) case (state_q)
        S_MONITOR: payload_pwm = 1'b1;
        S_SHAPE:   payload_pwm = (pwm_cnt < duty_q);
        default:   payload_pwm = 1'b0;
    endcase
endmodule