// Branch Target Buffer (BTB) Module
// 64-entry direct-mapped branch target cache providing zero-latency target prediction at Fetch stage.
module btb #(
    parameter BTB_ENTRIES = 64,
    parameter BTB_IDX_BITS = 6,
    parameter BTB_TAG_BITS = 24
) (
    input  logic                          clk,
    input  logic                          rst_n,

    // 1. Fetch Stage Lookup Port 0 (Combinational Read)
    input  pipeline_types::word_t         fetch_pc,
    output logic                          pred_hit,       // 1 if branch is found in BTB
    output pipeline_types::word_t         pred_target,    // Predicted destination PC

    // 1b. Fetch Stage Lookup Port 1 (Slot 1 Combinational Read)
    input  pipeline_types::word_t         fetch_pc1,
    output logic                          pred_hit1,
    output pipeline_types::word_t         pred_target1,

    // 2. Execute Stage Training / Update Port (Synchronous Write)
    input  logic                          update_en,      // Asserted when a branch executes/resolves
    input  pipeline_types::word_t         update_pc,      // Branch PC
    input  pipeline_types::word_t         update_target   // Real calculated target PC
);
    import pipeline_types::*;

    // BTB Entry Struct Definition
    typedef struct packed {
        logic                  valid;
        logic [BTB_TAG_BITS-1:0] tag;
        word_t                 target;
    } btb_entry_t;

    // 64-entry Direct-Mapped Storage Array
    btb_entry_t entries [0:BTB_ENTRIES-1];

    // Index & Tag Extraction - Port 0
    logic [BTB_IDX_BITS-1:0] fetch_idx;
    logic [BTB_TAG_BITS-1:0] fetch_tag;

    assign fetch_idx = fetch_pc[BTB_IDX_BITS+1:2];
    assign fetch_tag = fetch_pc[31:BTB_IDX_BITS+2];

    // Combinational Lookup - Port 0
    btb_entry_t lookup_entry;
    assign lookup_entry = entries[fetch_idx];

    assign pred_hit    = lookup_entry.valid && (lookup_entry.tag == fetch_tag);
    assign pred_target = lookup_entry.target;

    // Index & Tag Extraction - Port 1
    logic [BTB_IDX_BITS-1:0] fetch_idx1;
    logic [BTB_TAG_BITS-1:0] fetch_tag1;

    assign fetch_idx1 = fetch_pc1[BTB_IDX_BITS+1:2];
    assign fetch_tag1 = fetch_pc1[31:BTB_IDX_BITS+2];

    // Combinational Lookup - Port 1
    btb_entry_t lookup_entry1;
    assign lookup_entry1 = entries[fetch_idx1];

    assign pred_hit1    = lookup_entry1.valid && (lookup_entry1.tag == fetch_tag1);
    assign pred_target1 = lookup_entry1.target;

    // Synchronous Update / Training Port
    logic [BTB_IDX_BITS-1:0] update_idx;
    logic [BTB_TAG_BITS-1:0] update_tag;

    assign update_idx = update_pc[BTB_IDX_BITS+1:2];
    assign update_tag = update_pc[31:BTB_IDX_BITS+2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < BTB_ENTRIES; i++) begin
                entries[i] <= '0;
            end
        end else if (update_en) begin
            // Record / Update branch target entry
            entries[update_idx].valid  <= 1'b1;
            entries[update_idx].tag    <= update_tag;
            entries[update_idx].target <= update_target;
        end
    end
endmodule
