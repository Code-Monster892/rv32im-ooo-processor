// Physical Register Free List Module (R10K / RSD Style)
// Tracks unallocated physical register tags (p32..p63 at reset) in a 32-entry FIFO.
// Supports 2-Way Superscalar Dual-Allocation (popping up to 2 tags per cycle).
module free_list (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    flush,      // Resets Free List pointers on branch misprediction

    // Allocation Port 0 (Slot 0 / Legacy Port)
    input  logic                    alloc_req,  // Pop request for Slot 0
    output pipeline_types::p_reg_t  alloc_tag,  // Tag for Slot 0
    output logic                    empty,      // Asserted when Slot 0 cannot allocate

    // Allocation Port 1 (Slot 1 Superscalar Port)
    input  logic                    alloc_req1, // Pop request for Slot 1
    output pipeline_types::p_reg_t  alloc_tag1, // Tag for Slot 1
    output logic                    empty1,     // Asserted when Slot 1 cannot allocate

    // Non-Speculative Snapshot from Retirement RAT (for aliasing-free flush recovery)
    input  pipeline_types::p_reg_t  rrat_state [0:31],

    // Release / Retirement Port 0 (Slot 0)
    input  logic                    free_req,   // Push request (when Slot 0 commits at ROB head)
    input  pipeline_types::p_reg_t  free_tag,   // Returned physical register tag (old_p_dest)

    // Release / Retirement Port 1 (Slot 1)
    input  logic                    free_req1,  // Push request (when Slot 1 commits at ROB head)
    input  pipeline_types::p_reg_t  free_tag1   // Returned physical register tag (old_p_dest)
);
    import pipeline_types::*;

    // 32-entry FIFO array storing 6-bit physical register tags
    p_reg_t fifo [0:31];

    // Read (Head) and Write (Tail) Pointers
    logic [4:0] head;
    logic [4:0] tail;
    logic [5:0] count; // Counter from 0 to 32

    // Validity of allocation requests based on remaining tag count
    logic req0_valid, req1_valid;
    assign req0_valid = alloc_req && (count >= 6'd1) && !flush;
    assign req1_valid = alloc_req1 && (count >= (req0_valid ? 6'd2 : 6'd1)) && !flush;

    // Status Flags
    assign empty  = (count == 6'd0);
    assign empty1 = !req1_valid;

    // Combinational Outputs
    assign alloc_tag  = fifo[head];
    assign alloc_tag1 = fifo[head + (req0_valid ? 5'd1 : 5'd0)];

    // Net change in FIFO count
    logic [1:0] alloc_count;
    assign alloc_count = (req0_valid ? 2'd1 : 2'd0) + (req1_valid ? 2'd1 : 2'd0);

    logic [1:0] free_count;
    assign free_count = (free_req ? 2'd1 : 2'd0) + (free_req1 ? 2'd1 : 2'd0);

    // Synchronous FIFO State Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset State: Pre-fill FIFO with unallocated physical tags p32..p63
            head  <= 5'd0;
            tail  <= 5'd0;
            count <= 6'd32;
            for (int i = 0; i < 32; i++) begin
                fifo[i] <= p_reg_t'(6'd32 + 6'(i));
            end
        end else if (flush) begin
            // Dynamic Recovery from Committed RRAT State (Prevents physical-register aliasing)
            head  <= 5'd0;
            tail  <= 5'd0;
            begin
                logic [5:0] free_ptr;
                free_ptr = 6'd0;
                for (int p = 1; p < 64; p++) begin
                    logic used;
                    used = 1'b0;
                    for (int a = 0; a < 32; a++) begin
                        if (rrat_state[a] == p_reg_t'(6'(p))) used = 1'b1;
                    end
                    if (!used && free_ptr < 6'd32) begin
                        fifo[free_ptr[4:0]] <= p_reg_t'(6'(p));
                        free_ptr = free_ptr + 1'b1;
                    end
                end
                count <= free_ptr;
            end
        end else begin
            // 1. Advance Head Pointer (Pops)
            head <= head + 5'(alloc_count);

            // 2. Handle Release / Push (Up to 2 freed tags)
            if (free_req && free_req1) begin
                fifo[tail]        <= free_tag;
                fifo[tail + 5'd1] <= free_tag1;
                tail <= tail + 5'd2;
            end else if (free_req) begin
                fifo[tail] <= free_tag;
                tail       <= tail + 5'd1;
            end else if (free_req1) begin
                fifo[tail] <= free_tag1;
                tail       <= tail + 5'd1;
            end

            // 3. Update Tag Counter
            count <= count - 6'(alloc_count) + 6'(free_count);
        end
    end
endmodule
