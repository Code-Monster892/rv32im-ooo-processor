// GShare 2-Bit Saturating Counter Branch Direction Predictor (BHT) Module
// 256-entry Branch History Table using Global History Register (GHR) XOR hashing.
module bht #(
    parameter BHT_ENTRIES = 256,
    parameter GHR_BITS = 8
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // 1. Fetch Stage Lookup Port 0 (Combinational Read)
    input  pipeline_types::word_t         fetch_pc,
    output logic                          pred_taken,     // 1 if predicted Taken, 0 if Not Taken
    output logic [GHR_BITS-1:0]           curr_ghr,       // Snapshot of GHR at fetch time

    // 1b. Fetch Stage Lookup Port 1 (Slot 1 Combinational Read)
    input  pipeline_types::word_t         fetch_pc1,
    output logic                          pred_taken1,

    // 2. Execute Stage Training / Update Port (Synchronous Write)
    input  logic                          update_en,      // Asserted when a branch resolves
    input  pipeline_types::word_t         update_pc,      // Branch PC
    input  logic [GHR_BITS-1:0]           update_ghr,     // GHR snapshot when branch was fetched
    input  logic                          actual_taken    // True branch outcome from EX comparator
);
    import pipeline_types::*;

    // 256-entry table of 2-bit saturating counters
    // 2'b00: Strongly Not Taken, 2'b01: Weakly Not Taken, 2'b10: Weakly Taken, 2'b11: Strongly Taken
    logic [1:0] bht_table [0:BHT_ENTRIES-1];

    // Global History Register (Tracks last 8 branch outcomes)
    logic [GHR_BITS-1:0] ghr;
    assign curr_ghr = ghr;

    // 1. GShare Index Hash for Fetch Lookup - Port 0
    logic [GHR_BITS-1:0] fetch_idx;
    assign fetch_idx = fetch_pc[GHR_BITS+1:2] ^ ghr;
    assign pred_taken = bht_table[fetch_idx][1];

    // 1b. GShare Index Hash for Fetch Lookup - Port 1
    logic [GHR_BITS-1:0] fetch_idx1;
    assign fetch_idx1 = fetch_pc1[GHR_BITS+1:2] ^ ghr;
    assign pred_taken1 = bht_table[fetch_idx1][1];

    // 2. GShare Index Hash for Training / Update
    logic [GHR_BITS-1:0] update_idx;
    assign update_idx = update_pc[GHR_BITS+1:2] ^ update_ghr;

    // 3. Synchronous Update & GHR Shift
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ghr <= '0;
            // Initialize counters to Weakly Taken (2'b10)
            for (int i = 0; i < BHT_ENTRIES; i++) begin
                bht_table[i] <= 2'b10;
            end
        end else if (update_en) begin
            // Shift actual branch outcome into Global History Register
            ghr <= {ghr[GHR_BITS-2:0], actual_taken};

            // Update 2-bit Saturating Counter
            if (actual_taken) begin
                if (bht_table[update_idx] != 2'b11) begin
                    bht_table[update_idx] <= bht_table[update_idx] + 1'b1;
                end
            end else begin
                if (bht_table[update_idx] != 2'b00) begin
                    bht_table[update_idx] <= bht_table[update_idx] - 1'b1;
                end
            end
        end
    end
endmodule
