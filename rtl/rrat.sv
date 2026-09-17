// Retirement Register Alias Table (RRAT) Module
// Maintains the non-speculative architectural state of physical register mappings.
// Updates ONLY at ROB commit time and restores Active RAT on branch mispredict/exception.
module rrat (
    input  logic                          clk,
    input  logic                          rst_n,

    // Commit Port 0 from ROB Retirement Unit (Slot 0)
    rob_commit_if.Slave                   commit_in,

    // Commit Port 1 from ROB Retirement Unit (Slot 1)
    rob_commit_if.Slave                   commit_in1,

    // Snapshot Output to Active RAT (for 1-cycle flush recovery)
    output pipeline_types::p_reg_t        rrat_state [0:31]
);
    import pipeline_types::*;

    // 32-entry mapping table storing physical register tags
    p_reg_t map_table [0:31];
    p_reg_t eff_rrat  [0:31];

    // Compute effective committed mappings including current cycle's retiring instructions
    always_comb begin
        eff_rrat = map_table;
        if (commit_in.payload.valid && commit_in.payload.use_rd && (commit_in.payload.a_dest != 5'd0)) begin
            eff_rrat[commit_in.payload.a_dest] = commit_in.payload.p_dest;
        end
        if (commit_in1.payload.valid && commit_in1.payload.use_rd && (commit_in1.payload.a_dest != 5'd0)) begin
            eff_rrat[commit_in1.payload.a_dest] = commit_in1.payload.p_dest;
        end
    end

    // Expose continuous snapshot of non-speculative committed mappings
    assign rrat_state = eff_rrat;

    // Synchronous Update at Commit Time (Dual Superscalar)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset State: 1-to-1 identity mapping (x0 -> p0, x1 -> p1, ..., x31 -> p31)
            for (int i = 0; i < 32; i++) begin
                map_table[i] <= p_reg_t'(6'(i));
            end
        end else begin
            map_table <= eff_rrat;
        end
    end

endmodule
