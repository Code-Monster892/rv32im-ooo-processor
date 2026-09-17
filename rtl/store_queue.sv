// Store Queue (SQ) Module (R10K / RSD Paradigm)
// Buffers speculative store instructions and drains writes to RAM strictly at ROB commit time.
module store_queue #(
    parameter SQ_ENTRIES = 8,
    parameter SQ_IDX_BITS = 3,
    parameter ROB_IDX_BITS = 5
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,          // Clears uncommitted entries on branch mispredict

    // 1. Dispatch Allocation Port (from Rename/Dispatch)
    input  logic                          alloc_req,      // Instruction is a Store entering Dispatch
    input  pipeline_types::rob_id_t       alloc_rob_id,   // ROB tag assigned to this store
    output logic [SQ_IDX_BITS-1:0]        alloc_sq_idx,   // Allocated Store Queue index
    output logic                          full,           // Backpressure stall to dispatch when SQ is full

    // 2. Address & Data Fill Port (from AGU / Execution Unit)
    input  logic                          fill_addr_valid,
    input  logic [SQ_IDX_BITS-1:0]        fill_sq_idx,
    input  pipeline_types::word_t         fill_address,
    input  logic [3:0]                    fill_mask,

    input  logic                          fill_data_valid,
    input  pipeline_types::word_t         fill_data,

    // 3. Store-to-Load Forwarding Query Interface (for Load Queue)
    input  pipeline_types::word_t         fwd_query_addr,
    input  pipeline_types::rob_id_t       fwd_query_rob_id,
    input  logic [ROB_IDX_BITS-1:0]       rob_head_ptr,
    output logic                          fwd_hit,
    output pipeline_types::word_t         fwd_data,
    output logic [3:0]                    fwd_mask,
    output logic                          fwd_hazard,

    // 4. Non-Speculative Commit & RAM Write Port (Driven by ROB Head)
    input  logic                          commit_req,     // Asserted when ROB Head commits this store
    input  pipeline_types::rob_id_t       commit_rob_id,  // ROB ID of the committing store

    output logic                          mem_we,         // Physical RAM write enable
    output logic [3:0]                    mem_mask,       // Byte mask
    output pipeline_types::word_t         mem_address,    // Target RAM address
    output pipeline_types::word_t         mem_write_data, // Data to write to RAM
    output logic                          empty
);
    import pipeline_types::*;

    // Store Queue Entry Struct Definition
    typedef struct packed {
        logic       valid;
        rob_id_t    rob_id;
        logic       addr_valid;
        word_t      address;
        logic       data_valid;
        word_t      data;
        logic [3:0] mask;
    } sq_entry_t;

    // 8-entry Circular FIFO Store Queue Storage Array
    sq_entry_t entries [0:SQ_ENTRIES-1];

    // Circular FIFO Pointers & Counter
    logic [SQ_IDX_BITS-1:0] head_ptr;
    logic [SQ_IDX_BITS-1:0] tail_ptr;
    logic [SQ_IDX_BITS:0]   count;

    // Status Flags
    assign empty = (count == 0);
    assign full  = (count == SQ_ENTRIES);

    // Allocated index is current tail pointer
    assign alloc_sq_idx = tail_ptr;

    // Relative ROB Age Comparison (Circular FIFO Distance)
    function automatic logic is_older_rob(
        input rob_id_t a,
        input rob_id_t b,
        input logic [ROB_IDX_BITS-1:0] head
    );
        logic [ROB_IDX_BITS-1:0] dist_a, dist_b;
        dist_a = a[ROB_IDX_BITS-1:0] - head;
        dist_b = b[ROB_IDX_BITS-1:0] - head;
        return (dist_a < dist_b);
    endfunction

    // 1. Store-to-Load Forwarding Logic & Memory Disambiguation
    // Inspects stores older than query load in program order; detects hazards on unresolved addresses
    always_comb begin
        fwd_hit    = 1'b0;
        fwd_data   = 32'd0;
        fwd_mask   = 4'd0;
        fwd_hazard = 1'b0;

        for (int step = 0; step < SQ_ENTRIES; step++) begin
            logic [SQ_IDX_BITS-1:0] idx;
            idx = head_ptr + SQ_IDX_BITS'(step);
            if ((SQ_IDX_BITS+1)'(step) < count && entries[idx].valid) begin
                // Only consider stores that are STRICTLY OLDER than the querying load
                if (is_older_rob(entries[idx].rob_id, fwd_query_rob_id, rob_head_ptr)) begin
                    if (!entries[idx].addr_valid) begin
                        // Hazard: Older store address is unresolved! Could alias with load.
                        fwd_hazard = 1'b1;
                    end else if (entries[idx].address[31:2] == fwd_query_addr[31:2]) begin
                        // Addresses match!
                        if (!entries[idx].data_valid) begin
                            // Hazard: Older store aliases, but data is not ready yet.
                            fwd_hazard = 1'b1;
                        end else begin
                            fwd_hit = 1'b1;
                            if (entries[idx].mask[0]) begin fwd_data[7:0]   = entries[idx].data[7:0];   fwd_mask[0] = 1'b1; end
                            if (entries[idx].mask[1]) begin fwd_data[15:8]  = entries[idx].data[15:8];  fwd_mask[1] = 1'b1; end
                            if (entries[idx].mask[2]) begin fwd_data[23:16] = entries[idx].data[23:16]; fwd_mask[2] = 1'b1; end
                            if (entries[idx].mask[3]) begin fwd_data[31:24] = entries[idx].data[31:24]; fwd_mask[3] = 1'b1; end
                        end
                    end
                end
            end
        end
    end

    // 2. Non-Speculative Commit Output to Physical RAM
    sq_entry_t head_entry;
    assign head_entry = entries[head_ptr];

    logic can_drain;
    assign can_drain = !empty && head_entry.valid && head_entry.addr_valid && head_entry.data_valid &&
                       commit_req && (head_entry.rob_id == commit_rob_id);

    assign mem_we         = can_drain;
    assign mem_mask       = head_entry.mask;
    assign mem_address    = head_entry.address;
    assign mem_write_data = head_entry.data;

    // 3. Synchronous FIFO State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else if (flush) begin
            // Pipeline flush: Invalidate all uncommitted stores and reset pointers
            head_ptr <= '0;
            tail_ptr <= '0;
            count    <= '0;
            for (int i = 0; i < SQ_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else begin
            // A. Address Fill from AGU
            if (fill_addr_valid && entries[fill_sq_idx].valid) begin
                entries[fill_sq_idx].address    <= fill_address;
                entries[fill_sq_idx].mask       <= fill_mask;
                entries[fill_sq_idx].addr_valid <= 1'b1;
            end

            // B. Data Fill from PRF / CDB
            if (fill_data_valid && entries[fill_sq_idx].valid) begin
                entries[fill_sq_idx].data       <= fill_data;
                entries[fill_sq_idx].data_valid <= 1'b1;
            end

            // C. Simultaneous Allocation (Tail Push) and Drain (Head Pop)
            if (alloc_req && !full) begin
                entries[tail_ptr].valid      <= 1'b1;
                entries[tail_ptr].rob_id     <= alloc_rob_id;
                entries[tail_ptr].addr_valid <= 1'b0;
                entries[tail_ptr].data_valid <= 1'b0;
                entries[tail_ptr].address    <= 32'd0;
                entries[tail_ptr].data       <= 32'd0;
                entries[tail_ptr].mask       <= 4'd0;
                tail_ptr <= tail_ptr + 1'b1;
            end

            if (can_drain) begin
                if (!(alloc_req && !full && (head_ptr == tail_ptr))) begin
                    entries[head_ptr].valid <= 1'b0;
                end
                head_ptr <= head_ptr + 1'b1;
            end

            case ({alloc_req && !full, can_drain})
                2'b10: count <= count + 1'b1;
                2'b01: count <= count - 1'b1;
                default: ; // Count unchanged if both or neither
            endcase
        end
    end
endmodule
