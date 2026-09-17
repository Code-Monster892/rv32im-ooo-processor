// Register Alias Table (RAT) Module 
// Maps 32 Architectural Registers (x0..x31) to 64 Physical Registers (p0..p63).
// Supports 2-Way Superscalar Dual-Rename with Cross-Lane Dependency Forwarding.
module rat (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,        // Restores RAT state on branch mispredict / exception
    input  pipeline_types::p_reg_t        rrat_state [0:31], // Non-speculative snapshot from RRAT

    // Instruction Slot 0 Ports (Primary / Legacy)
    input  pipeline_types::a_reg_t        a_rs1,
    output pipeline_types::p_reg_t        p_src1,

    input  pipeline_types::a_reg_t        a_rs2,
    output pipeline_types::p_reg_t        p_src2,

    input  logic                          use_rd,       // 1 if Slot 0 writes destination reg
    input  pipeline_types::a_reg_t        a_rd,         // Slot 0 architectural destination reg index
    input  pipeline_types::p_reg_t        p_dest,       // Slot 0 physical tag from Free List
    output pipeline_types::p_reg_t        old_p_dest,   // Slot 0 previous physical tag

    // Instruction Slot 1 Ports (Superscalar Secondary Slot)
    input  pipeline_types::a_reg_t        a_rs1_1,
    output pipeline_types::p_reg_t        p_src1_1,

    input  pipeline_types::a_reg_t        a_rs2_1,
    output pipeline_types::p_reg_t        p_src2_1,

    input  logic                          use_rd1,      // 1 if Slot 1 writes destination reg
    input  pipeline_types::a_reg_t        a_rd1,        // Slot 1 architectural destination reg index
    input  pipeline_types::p_reg_t        p_dest1,      // Slot 1 physical tag from Free List
    output pipeline_types::p_reg_t        old_p_dest1   // Slot 1 previous physical tag
);
    import pipeline_types::*;

    // 32-entry RAT mapping table storing 6-bit physical register tags
    p_reg_t map_table [0:31];

    // 1. Slot 0 Read Ports
    assign p_src1     = (a_rs1 == 5'd0) ? 6'd0 : map_table[a_rs1];
    assign p_src2     = (a_rs2 == 5'd0) ? 6'd0 : map_table[a_rs2];
    assign old_p_dest = (a_rd  == 5'd0) ? 6'd0 : map_table[a_rd];

    // 2. Slot 1 Read Ports with Cross-Lane Dependency Forwarding
    // Check if Slot 1 reads the register that Slot 0 is writing this exact cycle!
    assign p_src1_1 = (a_rs1_1 == 5'd0) ? 6'd0 :
                      (use_rd && (a_rd != 5'd0) && (a_rs1_1 == a_rd)) ? p_dest :
                      map_table[a_rs1_1];

    assign p_src2_1 = (a_rs2_1 == 5'd0) ? 6'd0 :
                      (use_rd && (a_rd != 5'd0) && (a_rs2_1 == a_rd)) ? p_dest :
                      map_table[a_rs2_1];

    assign old_p_dest1 = (a_rd1 == 5'd0) ? 6'd0 :
                         (use_rd && (a_rd != 5'd0) && (a_rd1 == a_rd)) ? p_dest :
                         map_table[a_rd1];

    // 3. Synchronous State Update & Reset
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset State: 1-to-1 identity mapping (x0 -> p0, x1 -> p1, ..., x31 -> p31)
            for (int i = 0; i < 32; i++) begin
                map_table[i] <= p_reg_t'(6'(i));
            end
        end else if (flush) begin
            // 1-cycle restoration from committed RRAT snapshot
            map_table <= rrat_state;
        end else begin
            // Rename Update for Slot 0
            if (use_rd && (a_rd != 5'd0)) begin
                map_table[a_rd] <= p_dest;
            end

            // Rename Update for Slot 1 (Younger instruction takes precedence if both write same reg)
            if (use_rd1 && (a_rd1 != 5'd0)) begin
                map_table[a_rd1] <= p_dest1;
            end
        end
    end
endmodule
