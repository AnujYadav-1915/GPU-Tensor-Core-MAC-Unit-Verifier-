// =============================================================================
// Project: GPU Tensor Core MAC Unit Verifier
// Module: mac_bind
// Description: Binds the SystemVerilog Assertions module to the MAC unit.
// =============================================================================

bind mac_unit mac_sva #(
    .INPUT_WIDTH(INPUT_WIDTH),
    .ACCUM_WIDTH(ACCUM_WIDTH)
) u_mac_sva (
    .clk(clk),
    .rst_n(rst_n),
    .in_valid(in_valid),
    .out_ready(out_ready),
    .clr_accum(clr_accum),
    .sub_op(sub_op),
    .op_a(op_a),
    .op_b(op_b),
    .out_valid(out_valid),
    .in_ready(in_ready),
    .mac_out(mac_out),
    .overflow(overflow),
    .underflow(underflow),
    .current_state(current_state),
    .next_state(next_state),
    .s1_valid(s1_valid),
    .s2_valid(s2_valid),
    .s3_valid(s3_valid),
    .s1_product(s1_product),
    .s2_product(s2_product),
    .s2_accum_val(s2_accum_val),
    .pipe_stall(pipe_stall)
);
