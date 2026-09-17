// Unified Reservation Station (RS) Module (R10K / RSD Paradigm)
// Holds in-flight waiting instructions, snoops CDB for operand wakeup, and issues ready instructions out-of-order.
// Supports 2-Way Superscalar Dual-Dispatch and Dual-Issue.
module reservation_station #(
    parameter RS_ENTRIES = 8
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,          // Flushes active entries on branch mispredict

    // 1. Dispatch Allocation Ports (from Rename/Dispatch)
    input  logic                          alloc_req0,     // Qualified firing signal for Slot 0
    rename_dispatch_if.Slave              disp_in,
    input  pipeline_types::rob_id_t       alloc_rob_id,   // ROB tag assigned to Slot 0
    output logic                          full,           // Backpressure when RS cannot take Slot 0

    input  logic                          alloc_req1,     // Qualified firing signal for Slot 1
    rename_dispatch_if.Slave              disp_in1,
    input  pipeline_types::rob_id_t       alloc_rob_id1,  // ROB tag assigned to Slot 1
    output logic                          full1,          // Backpressure when RS cannot take 2 instructions

    // 2. Common Data Bus (CDB) Monitor for Dynamic Operand Wakeup
    cdb_if.Monitor                        cdb,

    // 3. PRF Read Interfaces for Issued Instructions
    // Port 0 PRF Reads
    output pipeline_types::p_reg_t        issue_p_src1,
    input  pipeline_types::word_t         issue_src1_val,
    output pipeline_types::p_reg_t        issue_p_src2,
    input  pipeline_types::word_t         issue_src2_val,

    // Port 1 PRF Reads (for ALU 1)
    output pipeline_types::p_reg_t        issue_p_src3,
    input  pipeline_types::word_t         issue_src3_val,
    output pipeline_types::p_reg_t        issue_p_src4,
    input  pipeline_types::word_t         issue_src4_val,

    // 4. Issue Ports (to Functional Execution Units)
    issue_if.Master                       issue_out,
    output pipeline_types::exec_unit_t    issue_exec_unit,

    issue_if.Master                       issue_out1,
    output pipeline_types::exec_unit_t    issue_exec_unit1
);
    import pipeline_types::*;

    // RS Entry Struct Definition (Stores tags and readiness only, NO wide 32-bit data)
    typedef struct packed {
        logic       valid;
        word_t      pc;
        rob_id_t    rob_id;
        exec_unit_t exec_unit;
        alu_op_t    alu_op;
        logic [2:0] funct3;
        word_t      imm;
        p_reg_t     p_src1;
        logic       src1_ready;
        p_reg_t     p_src2;
        logic       src2_ready;
        p_reg_t     p_dest;
        logic       use_rd;
        logic [2:0] lsq_idx;
        logic       use_rs2;
        logic       is_branch;
        logic       is_jump;
        logic       is_jalr;
        logic       is_auipc;
        logic       pred_taken;
        word_t      pred_target;
        logic [7:0] ghr;
    } rs_entry_t;

    // Unified Reservation Station Storage Array
    rs_entry_t entries [0:RS_ENTRIES-1];

    // 1. Free Slot Detection for Dispatch Allocation
    logic [RS_ENTRIES-1:0] free_slots;
    logic [$clog2(RS_ENTRIES)-1:0] alloc_idx0, alloc_idx1;
    logic alloc_found0, alloc_found1;

    always_comb begin
        for (int i = 0; i < RS_ENTRIES; i++) begin
            free_slots[i] = !entries[i].valid;
        end
    end

    // Priority Encoder to find up to two free slots
    always_comb begin
        alloc_idx0   = '0;
        alloc_found0 = 1'b0;
        alloc_idx1   = '0;
        alloc_found1 = 1'b0;

        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (free_slots[i]) begin
                if (!alloc_found0) begin
                    alloc_idx0   = i[$clog2(RS_ENTRIES)-1:0];
                    alloc_found0 = 1'b1;
                end else if (!alloc_found1) begin
                    alloc_idx1   = i[$clog2(RS_ENTRIES)-1:0];
                    alloc_found1 = 1'b1;
                end
            end
        end
    end

    assign full  = !alloc_found0;
    assign full1 = !alloc_found1;

    // 2. Dynamic Ready Detection & Age-Based Issue Arbitration
    logic [RS_ENTRIES-1:0] ready_mask;
    always_comb begin
        for (int i = 0; i < RS_ENTRIES; i++) begin
            ready_mask[i] = entries[i].valid && entries[i].src1_ready && entries[i].src2_ready;
        end
    end

    // Issue 0 Selection (Oldest available ready instruction)
    logic [$clog2(RS_ENTRIES)-1:0] issue_idx0;
    logic issue_found0;

    always_comb begin
        issue_idx0   = '0;
        issue_found0 = 1'b0;
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (ready_mask[i] && !issue_found0) begin
                issue_idx0   = i[$clog2(RS_ENTRIES)-1:0];
                issue_found0 = 1'b1;
            end
        end
    end

    // Issue 1 Selection (Second ready instruction, dedicated to ALU1)
    logic [$clog2(RS_ENTRIES)-1:0] issue_idx1;
    logic issue_found1;

    always_comb begin
        issue_idx1   = '0;
        issue_found1 = 1'b0;
        for (int i = 0; i < RS_ENTRIES; i++) begin
            if (ready_mask[i] && (i[$clog2(RS_ENTRIES)-1:0] != issue_idx0) && (entries[i].exec_unit == UNIT_ALU) && !issue_found1) begin
                issue_idx1   = i[$clog2(RS_ENTRIES)-1:0];
                issue_found1 = 1'b1;
            end
        end
    end

    // Selected Ready Entries
    rs_entry_t issued_entry0, issued_entry1;
    assign issued_entry0 = entries[issue_idx0];
    assign issued_entry1 = entries[issue_idx1];

    // Drive PRF Read Ports for Issued Instructions
    assign issue_p_src1 = issued_entry0.p_src1;
    assign issue_p_src2 = issued_entry0.p_src2;
    assign issue_p_src3 = issued_entry1.p_src1;
    assign issue_p_src4 = issued_entry1.p_src2;

    // Drive Issue Port 0 Interface
    assign issue_out.valid          = issue_found0;
    assign issue_out.pc             = issued_entry0.pc;
    assign issue_out.src1_val       = (issued_entry0.p_src1 == 6'd0) ? 32'd0 : issue_src1_val;
    assign issue_out.src2_val       = (issued_entry0.p_src2 == 6'd0) ? 32'd0 : issue_src2_val;
    assign issue_out.imm            = issued_entry0.imm;
    assign issue_out.alu_op         = issued_entry0.alu_op;
    assign issue_out.funct3         = issued_entry0.funct3;
    assign issue_out.p_dest         = issued_entry0.p_dest;
    assign issue_out.rob_id         = issued_entry0.rob_id;
    assign issue_out.lsq_idx        = issued_entry0.lsq_idx;
    assign issue_out.use_rs2        = issued_entry0.use_rs2;
    assign issue_out.is_branch      = issued_entry0.is_branch;
    assign issue_out.is_jump        = issued_entry0.is_jump;
    assign issue_out.is_jalr        = issued_entry0.is_jalr;
    assign issue_out.is_auipc       = issued_entry0.is_auipc;
    assign issue_out.pred_taken     = issued_entry0.pred_taken;
    assign issue_out.pred_target    = issued_entry0.pred_target;
    assign issue_out.ghr            = issued_entry0.ghr;
    assign issue_exec_unit          = issued_entry0.exec_unit;

    // Drive Issue Port 1 Interface (ALU 1)
    assign issue_out1.valid         = issue_found1;
    assign issue_out1.pc            = issued_entry1.pc;
    assign issue_out1.src1_val      = (issued_entry1.p_src1 == 6'd0) ? 32'd0 : issue_src3_val;
    assign issue_out1.src2_val      = (issued_entry1.p_src2 == 6'd0) ? 32'd0 : issue_src4_val;
    assign issue_out1.imm           = issued_entry1.imm;
    assign issue_out1.alu_op        = issued_entry1.alu_op;
    assign issue_out1.funct3        = issued_entry1.funct3;
    assign issue_out1.p_dest        = issued_entry1.p_dest;
    assign issue_out1.rob_id        = issued_entry1.rob_id;
    assign issue_out1.lsq_idx       = issued_entry1.lsq_idx;
    assign issue_out1.use_rs2       = issued_entry1.use_rs2;
    assign issue_out1.is_branch     = issued_entry1.is_branch;
    assign issue_out1.is_jump       = issued_entry1.is_jump;
    assign issue_out1.is_jalr       = issued_entry1.is_jalr;
    assign issue_out1.is_auipc      = issued_entry1.is_auipc;
    assign issue_out1.pred_taken    = issued_entry1.pred_taken;
    assign issue_out1.pred_target   = issued_entry1.pred_target;
    assign issue_out1.ghr           = issued_entry1.ghr;
    assign issue_exec_unit1         = issued_entry1.exec_unit;

    // 3. Synchronous State Updates: Dispatch, Wakeup, and Issue
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            for (int i = 0; i < RS_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else begin
            // Phase A: Dynamic Operand Wakeup (CDB Snooping on Active Entries)
            if (cdb.payload.valid && (cdb.payload.p_dest != 6'd0)) begin
                for (int i = 0; i < RS_ENTRIES; i++) begin
                    if (entries[i].valid) begin
                        if (!entries[i].src1_ready && (entries[i].p_src1 == cdb.payload.p_dest)) begin
                            entries[i].src1_ready <= 1'b1;
                        end
                        if (!entries[i].src2_ready && (entries[i].p_src2 == cdb.payload.p_dest)) begin
                            entries[i].src2_ready <= 1'b1;
                        end
                    end
                end
            end

            // Phase B: Issue Execution Unit Deallocation
            if (issue_found0 && issue_out.ready) begin
                entries[issue_idx0].valid <= 1'b0;
            end
            if (issue_found1 && issue_out1.ready) begin
                entries[issue_idx1].valid <= 1'b0;
            end

            // Phase C: Dispatch Allocation - Slot 0
            if (alloc_req0) begin
                entries[alloc_idx0].valid       <= 1'b1;
                entries[alloc_idx0].pc          <= disp_in.data.pc;
                entries[alloc_idx0].rob_id      <= alloc_rob_id;
                entries[alloc_idx0].exec_unit   <= disp_in.data.exec_unit;
                entries[alloc_idx0].alu_op      <= disp_in.data.alu_op;
                entries[alloc_idx0].funct3      <= disp_in.data.funct3;
                entries[alloc_idx0].imm         <= disp_in.data.imm;
                entries[alloc_idx0].p_src1      <= disp_in.data.p_src1;
                entries[alloc_idx0].p_src2      <= disp_in.data.p_src2;
                entries[alloc_idx0].p_dest      <= disp_in.data.p_dest;
                entries[alloc_idx0].use_rd      <= disp_in.data.use_rd;
                entries[alloc_idx0].lsq_idx     <= disp_in.data.lsq_idx;
                entries[alloc_idx0].use_rs2     <= disp_in.data.use_rs2;
                entries[alloc_idx0].is_branch   <= disp_in.data.is_branch;
                entries[alloc_idx0].is_jump     <= disp_in.data.is_jump;
                entries[alloc_idx0].is_jalr     <= disp_in.data.is_jalr;
                entries[alloc_idx0].is_auipc    <= disp_in.data.is_auipc;
                entries[alloc_idx0].pred_taken  <= disp_in.data.pred_taken;
                entries[alloc_idx0].pred_target <= disp_in.data.pred_target;
                entries[alloc_idx0].ghr         <= disp_in.data.ghr;

                // Check initial readiness
                if (disp_in.data.p_src1 == 6'd0 || disp_in.data.src1_ready ||
                   (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && disp_in.data.p_src1 == cdb.payload.p_dest)) begin
                    entries[alloc_idx0].src1_ready <= 1'b1;
                end else begin
                    entries[alloc_idx0].src1_ready <= 1'b0;
                end

                if (disp_in.data.p_src2 == 6'd0 || disp_in.data.src2_ready ||
                   (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && disp_in.data.p_src2 == cdb.payload.p_dest)) begin
                    entries[alloc_idx0].src2_ready <= 1'b1;
                end else begin
                    entries[alloc_idx0].src2_ready <= 1'b0;
                end
            end

            // Phase C: Dispatch Allocation - Slot 1
            if (alloc_req1) begin
                entries[alloc_idx1].valid       <= 1'b1;
                entries[alloc_idx1].pc          <= disp_in1.data.pc;
                entries[alloc_idx1].rob_id      <= alloc_rob_id1;
                entries[alloc_idx1].exec_unit   <= disp_in1.data.exec_unit;
                entries[alloc_idx1].alu_op      <= disp_in1.data.alu_op;
                entries[alloc_idx1].funct3      <= disp_in1.data.funct3;
                entries[alloc_idx1].imm         <= disp_in1.data.imm;
                entries[alloc_idx1].p_src1      <= disp_in1.data.p_src1;
                entries[alloc_idx1].p_src2      <= disp_in1.data.p_src2;
                entries[alloc_idx1].p_dest      <= disp_in1.data.p_dest;
                entries[alloc_idx1].use_rd      <= disp_in1.data.use_rd;
                entries[alloc_idx1].lsq_idx     <= disp_in1.data.lsq_idx;
                entries[alloc_idx1].use_rs2     <= disp_in1.data.use_rs2;
                entries[alloc_idx1].is_branch   <= disp_in1.data.is_branch;
                entries[alloc_idx1].is_jump     <= disp_in1.data.is_jump;
                entries[alloc_idx1].is_jalr     <= disp_in1.data.is_jalr;
                entries[alloc_idx1].is_auipc    <= disp_in1.data.is_auipc;
                entries[alloc_idx1].pred_taken  <= disp_in1.data.pred_taken;
                entries[alloc_idx1].pred_target <= disp_in1.data.pred_target;
                entries[alloc_idx1].ghr         <= disp_in1.data.ghr;

                // Check initial readiness
                if (disp_in1.data.p_src1 == 6'd0 || disp_in1.data.src1_ready ||
                   (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && disp_in1.data.p_src1 == cdb.payload.p_dest)) begin
                    entries[alloc_idx1].src1_ready <= 1'b1;
                end else begin
                    entries[alloc_idx1].src1_ready <= 1'b0;
                end

                if (disp_in1.data.p_src2 == 6'd0 || disp_in1.data.src2_ready ||
                   (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && disp_in1.data.p_src2 == cdb.payload.p_dest)) begin
                    entries[alloc_idx1].src2_ready <= 1'b1;
                end else begin
                    entries[alloc_idx1].src2_ready <= 1'b0;
                end
            end
        end
    end

    integer rs_cyc = 0;
    always_ff @(posedge clk) begin
        if (!rst_n) rs_cyc <= 0;
        else rs_cyc <= rs_cyc + 1;
    end

endmodule
