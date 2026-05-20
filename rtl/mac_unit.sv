// =============================================================================
// Project: GPU Tensor Core MAC Unit Verifier
// Module: mac_unit
// Description: Parameterized, high-throughput pipelined MAC unit with
//              saturation, overflow protection, and control FSM.
//              Designed for deep learning datapath verification.
// =============================================================================

`timescale 1ns/1ps

module mac_unit #(
    parameter int INPUT_WIDTH  = 16,
    parameter int ACCUM_WIDTH  = 32
)(
    input  logic                   clk,
    input  logic                   rst_n,

    // Control and Data Inputs
    input  logic                   in_valid,
    output logic                   out_ready,
    input  logic                   clr_accum,   // Force clear the internal accumulator
    input  logic                   sub_op,      // Perform A*B - Acc instead of A*B + Acc
    input  logic [INPUT_WIDTH-1:0] op_a,
    input  logic [INPUT_WIDTH-1:0] op_b,

    // Data Outputs
    output logic                   out_valid,
    input  logic                   in_ready,
    output logic [ACCUM_WIDTH-1:0] mac_out,
    output logic                   overflow,
    output logic                   underflow
);

    // Maximum and Minimum limits for saturation logic (signed)
    localparam logic [ACCUM_WIDTH-1:0] MAX_LIMIT = {1'b0, {(ACCUM_WIDTH-1){1'b1}}};
    localparam logic [ACCUM_WIDTH-1:0] MIN_LIMIT = {1'b1, {(ACCUM_WIDTH-1){1'b0}}};

    // FSM States for MAC Operation
    typedef enum logic [1:0] {
        STATE_IDLE  = 2'b00,
        STATE_RUN   = 2'b01,
        STATE_STALL = 2'b10,
        STATE_ERROR = 2'b11
    } state_t;

    state_t current_state, next_state;

    // --- Stage 1 Pipeline Registers ---
    logic                    s1_valid;
    logic                    s1_clr_accum;
    logic                    s1_sub_op;
    logic signed [INPUT_WIDTH*2-1:0] s1_product;

    // --- Stage 2 Pipeline Registers ---
    logic                    s2_valid;
    logic                    s2_clr_accum;
    logic                    s2_sub_op;
    logic signed [INPUT_WIDTH*2-1:0] s2_product;
    logic signed [ACCUM_WIDTH-1:0]   s2_accum_val;

    // --- Stage 3 Output Registers ---
    logic                    s3_valid;
    logic [ACCUM_WIDTH-1:0]  s3_mac_out;
    logic                    s3_overflow;
    logic                    s3_underflow;

    // Handshake controls
    logic pipe_stall;
    assign out_ready = (current_state != STATE_STALL) && (current_state != STATE_ERROR);
    assign pipe_stall = in_ready ? 1'b0 : s3_valid;

    // FSM Transitions
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            current_state <= STATE_IDLE;
        end else begin
            current_state <= next_state;
        end
    end

    always_comb begin
        next_state = current_state;
        case (current_state)
            STATE_IDLE: begin
                if (in_valid)
                    next_state = STATE_RUN;
            end
            STATE_RUN: begin
                if (pipe_stall)
                    next_state = STATE_STALL;
                else if (s3_overflow || s3_underflow)
                    next_state = STATE_ERROR;
                else if (!in_valid && !s1_valid && !s2_valid)
                    next_state = STATE_IDLE;
            end
            STATE_STALL: begin
                if (!pipe_stall) begin
                    if (s3_overflow || s3_underflow)
                        next_state = STATE_ERROR;
                    else
                        next_state = STATE_RUN;
                end
            end
            STATE_ERROR: begin
                // Error state requires reset or clearing accumulator to recover
                if (clr_accum)
                    next_state = STATE_IDLE;
            end
            default: next_state = STATE_IDLE;
        endcase
    end

    // =========================================================================
    // Pipeline Stage 1: Multiplication
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid     <= 1'b0;
            s1_clr_accum <= 1'b0;
            s1_sub_op    <= 1'b0;
            s1_product   <= '0;
        end else if (!pipe_stall) begin
            s1_valid     <= in_valid && out_ready;
            s1_clr_accum <= clr_accum;
            s1_sub_op    <= sub_op;
            s1_product   <= $signed(op_a) * $signed(op_b);
        end
    end

    // =========================================================================
    // Pipeline Stage 2: Accumulation Selection
    // =========================================================================
    // Maintain internal accumulator register for loopbacks
    logic signed [ACCUM_WIDTH-1:0] accum_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid     <= 1'b0;
            s2_clr_accum <= 1'b0;
            s2_sub_op    <= 1'b0;
            s2_product   <= '0;
            s2_accum_val <= '0;
        end else if (!pipe_stall) begin
            s2_valid     <= s1_valid;
            s2_clr_accum <= s1_clr_accum;
            s2_sub_op    <= s1_sub_op;
            s2_product   <= s1_product;
            s2_accum_val <= accum_reg;
        end
    end

    // =========================================================================
    // Pipeline Stage 3: Accumulate, Saturation & Saturation Detection
    // =========================================================================
    logic signed [ACCUM_WIDTH:0]   raw_sum;     // Extra bit for sign extension overflow check
    logic signed [ACCUM_WIDTH-1:0] operand_acc;
    logic signed [ACCUM_WIDTH-1:0] operand_prod;

    assign operand_acc  = s2_clr_accum ? '0 : s2_accum_val;
    // Sign extend multiplication product to match accumulator width
    assign operand_prod = $signed(s2_product);

    always_comb begin
        if (s2_sub_op)
            raw_sum = $signed(operand_acc) - $signed(operand_prod);
        else
            raw_sum = $signed(operand_acc) + $signed(operand_prod);
    end

    // Saturation and Overflow/Underflow Generation
    logic overflow_detected;
    logic underflow_detected;
    logic [ACCUM_WIDTH-1:0] saturated_sum;

    always_comb begin
        overflow_detected  = 1'b0;
        underflow_detected = 1'b0;
        saturated_sum      = raw_sum[ACCUM_WIDTH-1:0];

        // Check for positive overflow: positive + positive = negative
        if (!s2_sub_op && (operand_acc >= 0) && (operand_prod >= 0) && (raw_sum[ACCUM_WIDTH-1] == 1'b1)) begin
            overflow_detected = 1'b1;
            saturated_sum     = MAX_LIMIT;
        end
        // Check for negative underflow: negative + negative = positive
        else if (!s2_sub_op && (operand_acc < 0) && (operand_prod < 0) && (raw_sum[ACCUM_WIDTH-1] == 1'b0)) begin
            underflow_detected = 1'b1;
            saturated_sum      = MIN_LIMIT;
        end
        // For subtraction (Acc - Prod):
        // Acc positive, Prod negative (so adding positive): check for overflow
        else if (s2_sub_op && (operand_acc >= 0) && (operand_prod < 0) && (raw_sum[ACCUM_WIDTH-1] == 1'b1)) begin
            overflow_detected = 1'b1;
            saturated_sum     = MAX_LIMIT;
        end
        // Acc negative, Prod positive (so subtracting positive): check for underflow
        else if (s2_sub_op && (operand_acc < 0) && (operand_prod >= 0) && (raw_sum[ACCUM_WIDTH-1] == 1'b0)) begin
            underflow_detected = 1'b1;
            saturated_sum      = MIN_LIMIT;
        end
    end

    // Update internal accumulator and pipeline output registers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accum_reg    <= '0;
            s3_valid     <= 1'b0;
            s3_mac_out   <= '0;
            s3_overflow  <= 1'b0;
            s3_underflow <= 1'b0;
        end else if (clr_accum) begin
            accum_reg    <= '0;
            s3_valid     <= 1'b0;
            s3_mac_out   <= '0;
            s3_overflow  <= 1'b0;
            s3_underflow <= 1'b0;
        end else if (!pipe_stall) begin
            s3_valid     <= s2_valid;
            s3_mac_out   <= saturated_sum;
            s3_overflow  <= overflow_detected;
            s3_underflow <= underflow_detected;
            if (s2_valid) begin
                accum_reg <= saturated_sum;
            end
        end
    end

    // Interface outputs drive
    assign mac_out   = s3_mac_out;
    assign out_valid = s3_valid;
    assign overflow  = s3_overflow;
    assign underflow = s3_underflow;

endmodule
