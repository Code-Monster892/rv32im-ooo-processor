// Common Data Bus (CDB) Arbiter Module with Skid Buffer Retention
// Arbitrates completion broadcasts between ALU0, ALU1, Multiplier, and Memory execution units.
// Includes internal holding registers (skid buffers) so losing producers never drop results.
module cdb_arbiter (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,

    // Execution Unit 1: ALU0 Result Input
    input  logic                          alu_valid,
    input  pipeline_types::p_reg_t        alu_p_dest,
    input  pipeline_types::word_t         alu_value,
    input  pipeline_types::rob_id_t       alu_rob_id,
    output logic                          alu_ready,

    // Execution Unit 2: Multiplier Result Input
    input  logic                          mul_valid,
    input  pipeline_types::p_reg_t        mul_p_dest,
    input  pipeline_types::word_t         mul_value,
    input  pipeline_types::rob_id_t       mul_rob_id,
    output logic                          mul_ready,

    // Execution Unit 3: Memory / Load Result Input
    input  logic                          mem_valid,
    input  pipeline_types::p_reg_t        mem_p_dest,
    input  pipeline_types::word_t         mem_value,
    input  pipeline_types::rob_id_t       mem_rob_id,
    output logic                          mem_ready,

    // Execution Unit 4: Second ALU (ALU1) Result Input
    input  logic                          alu1_valid,
    input  pipeline_types::p_reg_t        alu1_p_dest,
    input  pipeline_types::word_t         alu1_value,
    input  pipeline_types::rob_id_t       alu1_rob_id,
    output logic                          alu1_ready,

    // Common Data Bus (CDB) Master Broadcast
    cdb_if.Master                         cdb_out
);
    import pipeline_types::*;

    // Skid Buffer Storage for Producers
    logic    alu_hold_valid;
    p_reg_t  alu_hold_p_dest;
    word_t   alu_hold_value;
    rob_id_t alu_hold_rob_id;

    logic    mul_hold_valid;
    p_reg_t  mul_hold_p_dest;
    word_t   mul_hold_value;
    rob_id_t mul_hold_rob_id;

    logic    alu1_hold_valid;
    p_reg_t  alu1_hold_p_dest;
    word_t   alu1_hold_value;
    rob_id_t alu1_hold_rob_id;

    // Effective candidate signals (Held result takes priority)
    logic    eff_alu_valid;
    p_reg_t  eff_alu_p_dest;
    word_t   eff_alu_value;
    rob_id_t eff_alu_rob_id;

    assign eff_alu_valid  = alu_hold_valid ? 1'b1 : alu_valid;
    assign eff_alu_p_dest = alu_hold_valid ? alu_hold_p_dest : alu_p_dest;
    assign eff_alu_value  = alu_hold_valid ? alu_hold_value  : alu_value;
    assign eff_alu_rob_id = alu_hold_valid ? alu_hold_rob_id : alu_rob_id;

    logic    eff_mul_valid;
    p_reg_t  eff_mul_p_dest;
    word_t   eff_mul_value;
    rob_id_t eff_mul_rob_id;

    assign eff_mul_valid  = mul_hold_valid ? 1'b1 : mul_valid;
    assign eff_mul_p_dest = mul_hold_valid ? mul_hold_p_dest : mul_p_dest;
    assign eff_mul_value  = mul_hold_valid ? mul_hold_value  : mul_value;
    assign eff_mul_rob_id = mul_hold_valid ? mul_hold_rob_id : mul_rob_id;

    logic    eff_alu1_valid;
    p_reg_t  eff_alu1_p_dest;
    word_t   eff_alu1_value;
    rob_id_t eff_alu1_rob_id;

    assign eff_alu1_valid  = alu1_hold_valid ? 1'b1 : alu1_valid;
    assign eff_alu1_p_dest = alu1_hold_valid ? alu1_hold_p_dest : alu1_p_dest;
    assign eff_alu1_value  = alu1_hold_valid ? alu1_hold_value  : alu1_value;
    assign eff_alu1_rob_id = alu1_hold_valid ? alu1_hold_rob_id : alu1_rob_id;

    // Grants for effective candidates
    logic grant_mem, grant_mul, grant_alu, grant_alu1;

    // Priority Arbitration: Memory > Multiplier > ALU0 > ALU1
    always_comb begin
        grant_mem  = 1'b0;
        grant_mul  = 1'b0;
        grant_alu  = 1'b0;
        grant_alu1 = 1'b0;

        if (mem_valid) begin
            cdb_out.payload.valid  = 1'b1;
            cdb_out.payload.p_dest = mem_p_dest;
            cdb_out.payload.value  = mem_value;
            cdb_out.payload.rob_id = mem_rob_id;
            grant_mem              = 1'b1;
        end else if (eff_mul_valid) begin
            cdb_out.payload.valid  = 1'b1;
            cdb_out.payload.p_dest = eff_mul_p_dest;
            cdb_out.payload.value  = eff_mul_value;
            cdb_out.payload.rob_id = eff_mul_rob_id;
            grant_mul              = 1'b1;
        end else if (eff_alu_valid) begin
            cdb_out.payload.valid  = 1'b1;
            cdb_out.payload.p_dest = eff_alu_p_dest;
            cdb_out.payload.value  = eff_alu_value;
            cdb_out.payload.rob_id = eff_alu_rob_id;
            grant_alu              = 1'b1;
        end else if (eff_alu1_valid) begin
            cdb_out.payload.valid  = 1'b1;
            cdb_out.payload.p_dest = eff_alu1_p_dest;
            cdb_out.payload.value  = eff_alu1_value;
            cdb_out.payload.rob_id = eff_alu1_rob_id;
            grant_alu1             = 1'b1;
        end else begin
            cdb_out.payload.valid  = 1'b0;
            cdb_out.payload.p_dest = 6'd0;
            cdb_out.payload.value  = 32'd0;
            cdb_out.payload.rob_id = 6'd0;
        end
    end

    // Interface ready signals to producers:
    // A producer is accepted if it was directly granted OR if the skid buffer can take it
    assign mem_ready  = grant_mem;
    assign alu_ready  = (grant_alu && !alu_hold_valid) || (!alu_hold_valid);
    assign mul_ready  = (grant_mul && !mul_hold_valid) || (!mul_hold_valid);
    assign alu1_ready = (grant_alu1 && !alu1_hold_valid) || (!alu1_hold_valid);

    // Synchronous Skid Buffer State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            alu_hold_valid  <= 1'b0;
            alu_hold_p_dest <= 6'd0;
            alu_hold_value  <= 32'd0;
            alu_hold_rob_id <= 6'd0;

            mul_hold_valid  <= 1'b0;
            mul_hold_p_dest <= 6'd0;
            mul_hold_value  <= 32'd0;
            mul_hold_rob_id <= 6'd0;

            alu1_hold_valid  <= 1'b0;
            alu1_hold_p_dest <= 6'd0;
            alu1_hold_value  <= 32'd0;
            alu1_hold_rob_id <= 6'd0;
        end else begin
            // ALU0 Skid Buffer Update
            if (grant_alu) begin
                if (alu_hold_valid) begin
                    alu_hold_valid <= 1'b0;
                end
            end else if (alu_valid && !alu_hold_valid) begin
                alu_hold_valid  <= 1'b1;
                alu_hold_p_dest <= alu_p_dest;
                alu_hold_value  <= alu_value;
                alu_hold_rob_id <= alu_rob_id;
            end

            // Multiplier Skid Buffer Update
            if (grant_mul) begin
                if (mul_hold_valid) begin
                    mul_hold_valid <= 1'b0;
                end
            end else if (mul_valid && !mul_hold_valid) begin
                mul_hold_valid  <= 1'b1;
                mul_hold_p_dest <= mul_p_dest;
                mul_hold_value  <= mul_value;
                mul_hold_rob_id <= mul_rob_id;
            end

            // ALU1 Skid Buffer Update
            if (grant_alu1) begin
                if (alu1_hold_valid) begin
                    alu1_hold_valid <= 1'b0;
                end
            end else if (alu1_valid && !alu1_hold_valid) begin
                alu1_hold_valid  <= 1'b1;
                alu1_hold_p_dest <= alu1_p_dest;
                alu1_hold_value  <= alu1_value;
                alu1_hold_rob_id <= alu1_rob_id;
            end
        end
    end

endmodule
