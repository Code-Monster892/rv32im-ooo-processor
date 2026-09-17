// Reorder Buffer (ROB) Module (R10K / RSD Paradigm)
// 32-entry circular FIFO enforcing in-order retirement and safe tag release.
// Supports 2-Way Superscalar Dual-Allocation and Dual-Commit with Precise Exception/Branch Rollback.
module rob #(
    parameter ROB_ENTRIES = 32,
    parameter ROB_IDX_BITS = 5
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,          // Flushes in-flight speculative entries on mispredict

    // 1. Allocation Port 0 (Slot 0)
    input  logic                          alloc_req,      // Slot 0 Dispatch
    input  pipeline_types::word_t         alloc_pc,
    input  pipeline_types::a_reg_t        alloc_a_dest,   // Architectural destination register (x0..x31)
    input  pipeline_types::p_reg_t        alloc_p_dest,   // Allocated physical register (p0..p63)
    input  pipeline_types::p_reg_t        alloc_old_p_dest,// Old physical tag to release at commit
    input  logic                          alloc_use_rd,   // 1 if instruction writes a destination
    input  logic                          alloc_is_store, // 1 if instruction is a Store
    output pipeline_types::rob_id_t       alloc_rob_id,   // Allocated ROB ID returned to dispatch
    output logic                          full,           // ROB full (backpressure stall to dispatch)

    // Allocation Port 1 (Slot 1)
    input  logic                          alloc_req1,     // Slot 1 Dispatch
    input  pipeline_types::word_t         alloc_pc1,
    input  pipeline_types::a_reg_t        alloc_a_dest1,
    input  pipeline_types::p_reg_t        alloc_p_dest1,
    input  pipeline_types::p_reg_t        alloc_old_p_dest1,
    input  logic                          alloc_use_rd1,
    input  logic                          alloc_is_store1,
    output pipeline_types::rob_id_t       alloc_rob_id1,
    output logic                          full1,

    // 2. Writeback Port (Common Data Bus - CDB Monitor)
    cdb_if.Monitor                        cdb,

    // 3. Commit / Retirement Port (To Retirement Unit & Free List)
    rob_commit_if.Master                  commit_out,      // Slot 0 commit interface
    output logic                          commit_free_req, // Triggers Free List tag release (Slot 0)
    output pipeline_types::p_reg_t        commit_free_tag, // Tag released (Slot 0)
    output logic                          commit_is_store, // Asserted when Slot 0 committing is a store

    rob_commit_if.Master                  commit_out1,     // Slot 1 commit interface
    output logic                          commit_free_req1,// Triggers Free List tag release (Slot 1)
    output pipeline_types::p_reg_t        commit_free_tag1,// Tag released (Slot 1)
    output logic                          commit_is_store1,

    output logic                          empty,
    output logic [ROB_IDX_BITS-1:0]       rob_head_ptr,

    // Non-CDB Completion Port (for stores, branches, instructions without rd)
    input  logic                          non_cdb_complete_valid,
    input  pipeline_types::rob_id_t       non_cdb_complete_rob_id,

    // Branch Resolution Port (for branch outcome & misprediction detection)
    input  logic                          branch_complete_valid,
    input  pipeline_types::rob_id_t       branch_complete_rob_id,
    input  logic                          branch_mispredicted,
    input  pipeline_types::word_t         branch_correct_target
);
    import pipeline_types::*;

    // ROB Entry Struct Definition
    typedef struct packed {
        logic       valid;
        word_t      pc;
        a_reg_t     a_dest;
        p_reg_t     p_dest;
        p_reg_t     old_p_dest;
        logic       use_rd;
        logic       is_store;
        logic       completed;
        logic       mispredicted;
        word_t      correct_target;
    } rob_entry_t;

    // 32-entry circular FIFO storage array
    rob_entry_t entries [0:ROB_ENTRIES-1];

    // Circular FIFO Pointers & Counter
    logic [ROB_IDX_BITS-1:0] head_ptr;
    logic [ROB_IDX_BITS-1:0] tail_ptr;
    logic [ROB_IDX_BITS:0]   count;

    // Status Flags
    assign empty        = (count == 0);
    assign full         = (count >= ROB_ENTRIES);
    assign full1        = (count >= (ROB_ENTRIES - 1));
    assign rob_head_ptr = head_ptr;

    // Allocated ROB IDs
    assign alloc_rob_id  = rob_id_t'(6'(tail_ptr));
    assign alloc_rob_id1 = rob_id_t'(6'(tail_ptr + 1'b1));

    // Head Retirement Inspection (Combinational - Dual Superscalar)
    logic can_commit0, can_commit1;
    rob_entry_t head_entry0, head_entry1;
    logic [ROB_IDX_BITS-1:0] head_ptr1;

    assign head_ptr1   = head_ptr + 1'b1;
    assign head_entry0 = entries[head_ptr];
    assign head_entry1 = entries[head_ptr1];

    // Slot 0 can commit if ROB has at least 1 entry, entry 0 is valid and completed
    assign can_commit0 = (count >= 1) && head_entry0.valid && head_entry0.completed;

    // Slot 1 can commit ONLY IF Slot 0 commits AND does NOT mispredict AND ROB has at least 2 entries AND entry 1 is completed AND not a store
    assign can_commit1 = can_commit0 && !head_entry0.mispredicted && (count >= 2) && head_entry1.valid && head_entry1.completed && !head_entry1.is_store;

    // Drive Slot 0 rob_commit_if interface
    assign commit_out.payload.valid      = can_commit0;
    assign commit_out.payload.rob_id     = rob_id_t'(6'(head_ptr));
    assign commit_out.payload.pc         = head_entry0.pc;
    assign commit_out.payload.a_dest     = head_entry0.a_dest;
    assign commit_out.payload.p_dest     = head_entry0.p_dest;
    assign commit_out.payload.old_p_dest = head_entry0.old_p_dest;
    assign commit_out.payload.use_rd     = head_entry0.use_rd;
    assign commit_out.flush_out          = can_commit0 && head_entry0.mispredicted;
    assign commit_out.flush_pc           = head_entry0.correct_target;

    assign commit_free_req = can_commit0 && head_entry0.use_rd && (head_entry0.old_p_dest != 6'd0);
    assign commit_free_tag = head_entry0.old_p_dest;
    assign commit_is_store = can_commit0 && head_entry0.is_store;

    // Drive Slot 1 rob_commit_if interface
    assign commit_out1.payload.valid      = can_commit1;
    assign commit_out1.payload.rob_id     = rob_id_t'(6'(head_ptr1));
    assign commit_out1.payload.pc         = head_entry1.pc;
    assign commit_out1.payload.a_dest     = head_entry1.a_dest;
    assign commit_out1.payload.p_dest     = head_entry1.p_dest;
    assign commit_out1.payload.old_p_dest = head_entry1.old_p_dest;
    assign commit_out1.payload.use_rd     = head_entry1.use_rd;
    assign commit_out1.flush_out          = can_commit1 && head_entry1.mispredicted;
    assign commit_out1.flush_pc           = head_entry1.correct_target;

    assign commit_free_req1 = can_commit1 && head_entry1.use_rd && (head_entry1.old_p_dest != 6'd0);
    assign commit_free_tag1 = head_entry1.old_p_dest;
    assign commit_is_store1 = can_commit1 && head_entry1.is_store;

    // Number of committing instructions: 0, 1, or 2
    logic [1:0] num_commit;
    assign num_commit = (can_commit1 ? 2'd2 : (can_commit0 ? 2'd1 : 2'd0));

    // Number of allocated instructions
    logic [1:0] num_alloc;
    assign num_alloc = (alloc_req && alloc_req1 && !full1) ? 2'd2 :
                       (alloc_req && !full)                 ? 2'd1 : 2'd0;

    // Synchronous FIFO State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            for (int i = 0; i < ROB_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else if (flush) begin
            // Pipeline flush: Invalidate all uncommitted entries and reset pointers
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            for (int i = 0; i < ROB_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else begin
            // 1. CDB Writeback: Mark completed entries
            if (cdb.payload.valid) begin
                if (entries[cdb.payload.rob_id[ROB_IDX_BITS-1:0]].valid) begin
                    entries[cdb.payload.rob_id[ROB_IDX_BITS-1:0]].completed <= 1'b1;
                end
            end

            // 1b. Non-CDB Completion (Stores, instructions without rd)
            if (non_cdb_complete_valid) begin
                if (entries[non_cdb_complete_rob_id[ROB_IDX_BITS-1:0]].valid) begin
                    entries[non_cdb_complete_rob_id[ROB_IDX_BITS-1:0]].completed <= 1'b1;
                end
            end

            // 1c. Branch Resolution Completion
            if (branch_complete_valid) begin
                if (entries[branch_complete_rob_id[ROB_IDX_BITS-1:0]].valid) begin
                    if (!entries[branch_complete_rob_id[ROB_IDX_BITS-1:0]].use_rd ||
                         entries[branch_complete_rob_id[ROB_IDX_BITS-1:0]].p_dest == 6'd0) begin
                        entries[branch_complete_rob_id[ROB_IDX_BITS-1:0]].completed <= 1'b1;
                    end
                    entries[branch_complete_rob_id[ROB_IDX_BITS-1:0]].mispredicted   <= branch_mispredicted;
                    entries[branch_complete_rob_id[ROB_IDX_BITS-1:0]].correct_target <= branch_correct_target;
                end
            end

            // 2. Head Retirement Update (Pop up to 2 entries)
            if (can_commit1) begin
                entries[head_ptr].valid  <= 1'b0;
                entries[head_ptr1].valid <= 1'b0;
                head_ptr <= head_ptr + ROB_IDX_BITS'(2);
            end else if (can_commit0) begin
                entries[head_ptr].valid <= 1'b0;
                head_ptr <= head_ptr + ROB_IDX_BITS'(1);
            end

            // 3. Tail Allocation Update (Push up to 2 entries)
            if (num_alloc == 2'd2) begin
                // Push Slot 0
                entries[tail_ptr].valid          <= 1'b1;
                entries[tail_ptr].pc             <= alloc_pc;
                entries[tail_ptr].a_dest         <= alloc_a_dest;
                entries[tail_ptr].p_dest         <= alloc_p_dest;
                entries[tail_ptr].old_p_dest     <= alloc_old_p_dest;
                entries[tail_ptr].use_rd         <= alloc_use_rd;
                entries[tail_ptr].is_store       <= alloc_is_store;
                entries[tail_ptr].completed      <= 1'b0;
                entries[tail_ptr].mispredicted   <= 1'b0;
                entries[tail_ptr].correct_target <= 32'd0;

                // Push Slot 1
                entries[tail_ptr + 1'b1].valid          <= 1'b1;
                entries[tail_ptr + 1'b1].pc             <= alloc_pc1;
                entries[tail_ptr + 1'b1].a_dest         <= alloc_a_dest1;
                entries[tail_ptr + 1'b1].p_dest         <= alloc_p_dest1;
                entries[tail_ptr + 1'b1].old_p_dest     <= alloc_old_p_dest1;
                entries[tail_ptr + 1'b1].use_rd         <= alloc_use_rd1;
                entries[tail_ptr + 1'b1].is_store       <= alloc_is_store1;
                entries[tail_ptr + 1'b1].completed      <= 1'b0;
                entries[tail_ptr + 1'b1].mispredicted   <= 1'b0;
                entries[tail_ptr + 1'b1].correct_target <= 32'd0;

                tail_ptr <= tail_ptr + ROB_IDX_BITS'(2);
            end else if (num_alloc == 2'd1) begin
                entries[tail_ptr].valid          <= 1'b1;
                entries[tail_ptr].pc             <= alloc_pc;
                entries[tail_ptr].a_dest         <= alloc_a_dest;
                entries[tail_ptr].p_dest         <= alloc_p_dest;
                entries[tail_ptr].old_p_dest     <= alloc_old_p_dest;
                entries[tail_ptr].use_rd         <= alloc_use_rd;
                entries[tail_ptr].is_store       <= alloc_is_store;
                entries[tail_ptr].completed      <= 1'b0;
                entries[tail_ptr].mispredicted   <= 1'b0;
                entries[tail_ptr].correct_target <= 32'd0;

                tail_ptr <= tail_ptr + ROB_IDX_BITS'(1);
            end

            // 4. Overall Counter Update
            count <= count + (ROB_IDX_BITS+1)'(num_alloc) - (ROB_IDX_BITS+1)'(num_commit);
        end
    end
endmodule
