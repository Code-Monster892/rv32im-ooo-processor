// Load Queue (LQ) Module (R10K / RSD Paradigm)
// Manages speculative out-of-order load execution and Store-to-Load forwarding bypass.
module load_queue #(
    parameter LQ_ENTRIES = 8,
    parameter LQ_IDX_BITS = 3
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,          // Clears uncommitted entries on branch mispredict

    // 1. Dispatch Allocation Port (from Rename/Dispatch)
    input  logic                          alloc_req,      // Instruction is a Load entering Dispatch
    input  pipeline_types::rob_id_t       alloc_rob_id,   // ROB tag assigned to this load
    input  pipeline_types::p_reg_t        alloc_p_dest,   // Destination physical register tag
    input  logic [2:0]                    alloc_funct3,   // Load size / sign (LW, LH, LB, LHU, LBU)
    output logic [LQ_IDX_BITS-1:0]        alloc_lq_idx,   // Allocated Load Queue index
    output logic                          full,           // Backpressure stall to dispatch when LQ is full

    // 2. Address Execution Port (from AGU / Execution Unit)
    input  logic                          exec_addr_valid,
    input  logic [LQ_IDX_BITS-1:0]        exec_lq_idx,
    input  pipeline_types::word_t         exec_address,

    // 3. Store Queue (SQ) Forwarding & Disambiguation Query Interface
    output pipeline_types::word_t         sq_query_addr,
    output pipeline_types::rob_id_t       sq_query_rob_id,
    input  logic                          sq_fwd_hit,
    input  pipeline_types::word_t         sq_fwd_data,
    input  logic [3:0]                    sq_fwd_mask,
    input  logic                          sq_fwd_hazard,

    // 4. Physical RAM Read Interface
    output logic                          mem_read_en,
    output pipeline_types::word_t         mem_read_addr,
    input  pipeline_types::word_t         mem_read_data,

    // 5. Completion Broadcast Port (to CDB Arbiter)
    output logic                          wb_valid,
    output pipeline_types::p_reg_t        wb_p_dest,
    output pipeline_types::word_t         wb_data,
    output pipeline_types::rob_id_t       wb_rob_id,
    input  logic                          wb_ready,       // Granted by CDB Arbiter
    output logic                          empty
);
    import pipeline_types::*;

    // Load Queue Entry Struct Definition
    typedef struct packed {
        logic       valid;
        rob_id_t    rob_id;
        p_reg_t     p_dest;
        logic [2:0] funct3;
        logic       addr_valid;
        word_t      address;
        logic       completed;
        word_t      result_data;
    } lq_entry_t;

    // 8-entry Circular FIFO Load Queue Storage Array
    lq_entry_t entries [0:LQ_ENTRIES-1];

    // Circular FIFO Pointers & Counter
    logic [LQ_IDX_BITS-1:0] head_ptr;
    logic [LQ_IDX_BITS-1:0] tail_ptr;
    logic [LQ_IDX_BITS:0]   count;

    // Status Flags
    assign empty = (count == 0);
    assign full  = (count == LQ_ENTRIES);

    // Allocated index is current tail pointer
    assign alloc_lq_idx = tail_ptr;

    // Scan for oldest uncompleted pending load with a valid address
    logic pending_found;
    logic [LQ_IDX_BITS-1:0] pending_idx;

    always_comb begin
        pending_found = 1'b0;
        pending_idx   = '0;
        for (int step = 0; step < LQ_ENTRIES; step++) begin
            logic [LQ_IDX_BITS-1:0] idx;
            idx = head_ptr + LQ_IDX_BITS'(step);
            if ((LQ_IDX_BITS+1)'(step) < count && entries[idx].valid && entries[idx].addr_valid && !entries[idx].completed && !pending_found) begin
                pending_found = 1'b1;
                pending_idx   = idx;
            end
        end
    end

    // Active query multiplexing:
    // If an older load is pending, prioritize checking the pending load.
    // Otherwise, check the newly executing AGU load.
    logic active_query_valid;
    word_t active_query_addr;
    rob_id_t active_query_rob_id;
    logic [LQ_IDX_BITS-1:0] active_target_idx;
    logic active_is_exec;

    assign active_is_exec      = !pending_found && exec_addr_valid && entries[exec_lq_idx].valid;
    assign active_query_valid  = (exec_addr_valid && entries[exec_lq_idx].valid) || pending_found;
    assign active_target_idx   = pending_found ? pending_idx : exec_lq_idx;
    assign active_query_addr   = pending_found ? entries[pending_idx].address : exec_address;
    assign active_query_rob_id = entries[active_target_idx].rob_id;

    assign sq_query_addr   = active_query_addr;
    assign sq_query_rob_id = active_query_rob_id;

    // Read RAM when active query is valid, no hazard, and SQ doesn't supply all 4 bytes
    assign mem_read_en   = active_query_valid && !sq_fwd_hazard && (!sq_fwd_hit || sq_fwd_mask != 4'b1111);
    assign mem_read_addr = active_query_addr;

    // Byte lane merging between SQ forwarded bytes and RAM data
    word_t merged_word;
    always_comb begin
        merged_word[7:0]   = (sq_fwd_hit && sq_fwd_mask[0]) ? sq_fwd_data[7:0]   : mem_read_data[7:0];
        merged_word[15:8]  = (sq_fwd_hit && sq_fwd_mask[1]) ? sq_fwd_data[15:8]  : mem_read_data[15:8];
        merged_word[23:16] = (sq_fwd_hit && sq_fwd_mask[2]) ? sq_fwd_data[23:16] : mem_read_data[23:16];
        merged_word[31:24] = (sq_fwd_hit && sq_fwd_mask[3]) ? sq_fwd_data[31:24] : mem_read_data[31:24];
    end

    // Data Formatter / Sign Extender for Load Sub-types (LW, LH, LB, LHU, LBU)
    function automatic word_t format_load_data(
        input logic [2:0] funct3,
        input logic [1:0] offset,
        input word_t      raw_data
    );
        word_t formatted;
        case (funct3)
            3'b000: begin // LB (Signed byte)
                case (offset)
                    2'b00: formatted = {{24{raw_data[7]}},  raw_data[7:0]};
                    2'b01: formatted = {{24{raw_data[15]}}, raw_data[15:8]};
                    2'b10: formatted = {{24{raw_data[23]}}, raw_data[23:16]};
                    2'b11: formatted = {{24{raw_data[31]}}, raw_data[31:24]};
                endcase
            end
            3'b001: begin // LH (Signed halfword)
                case (offset[1])
                    1'b0: formatted = {{16{raw_data[15]}}, raw_data[15:0]};
                    1'b1: formatted = {{16{raw_data[31]}}, raw_data[31:16]};
                endcase
            end
            3'b010: formatted = raw_data; // LW (32-bit word)
            3'b100: begin // LBU (Unsigned byte)
                case (offset)
                    2'b00: formatted = {24'b0, raw_data[7:0]};
                    2'b01: formatted = {24'b0, raw_data[15:8]};
                    2'b10: formatted = {24'b0, raw_data[23:16]};
                    2'b11: formatted = {24'b0, raw_data[31:24]};
                endcase
            end
            3'b101: begin // LHU (Unsigned halfword)
                case (offset[1])
                    1'b0: formatted = {16'b0, raw_data[15:0]};
                    1'b1: formatted = {16'b0, raw_data[31:16]};
                endcase
            end
            default: formatted = raw_data;
        endcase
        return formatted;
    endfunction

    // Writeback Output to CDB Arbiter
    lq_entry_t head_entry;
    assign head_entry = entries[head_ptr];

    assign wb_valid   = !empty && head_entry.valid && head_entry.completed;
    assign wb_p_dest  = head_entry.p_dest;
    assign wb_data    = head_entry.result_data;
    assign wb_rob_id  = head_entry.rob_id;

    // Synchronous FIFO State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            for (int i = 0; i < LQ_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else if (flush) begin
            // Pipeline flush: Invalidate all speculative loads and reset pointers
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            for (int i = 0; i < LQ_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else begin
            // A. New AGU Address Execution
            if (exec_addr_valid && entries[exec_lq_idx].valid) begin
                entries[exec_lq_idx].address    <= exec_address;
                entries[exec_lq_idx].addr_valid <= 1'b1;

                // Complete immediately only if no older pending loads and no SQ hazard
                if (active_is_exec && !sq_fwd_hazard) begin
                    entries[exec_lq_idx].completed   <= 1'b1;
                    entries[exec_lq_idx].result_data <= format_load_data(entries[exec_lq_idx].funct3, exec_address[1:0], merged_word);
                end else begin
                    entries[exec_lq_idx].completed   <= 1'b0; // Wait in pending queue
                end
            end

            // B. Pending Load Replay & Completion
            if (pending_found && !sq_fwd_hazard) begin
                entries[pending_idx].completed   <= 1'b1;
                entries[pending_idx].result_data <= format_load_data(entries[pending_idx].funct3, entries[pending_idx].address[1:0], merged_word);
            end

            // B. Simultaneous Allocation (Tail Push) and Writeback Drain (Head Pop)
            if (alloc_req && !full) begin
                entries[tail_ptr].valid       <= 1'b1;
                entries[tail_ptr].rob_id      <= alloc_rob_id;
                entries[tail_ptr].p_dest      <= alloc_p_dest;
                entries[tail_ptr].funct3      <= alloc_funct3;
                entries[tail_ptr].addr_valid  <= 1'b0;
                entries[tail_ptr].completed   <= 1'b0;
                entries[tail_ptr].address     <= 32'd0;
                entries[tail_ptr].result_data <= 32'd0;
                tail_ptr <= tail_ptr + 1'b1;
            end

            if (wb_valid && wb_ready) begin
                if (!(alloc_req && !full && (head_ptr == tail_ptr))) begin
                    entries[head_ptr].valid <= 1'b0;
                end
                head_ptr <= head_ptr + 1'b1;
            end

            case ({alloc_req && !full, wb_valid && wb_ready})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ; // Count unchanged if both or neither
            endcase
        end
    end
endmodule
