// Physical Register File (PRF) Module (R10K / RSD Style)
// 64 x 32-bit physical storage array with 4 read ports, dual allocation, CDB writeback, and readiness bits.
module prf (
    input  logic                    clk,
    input  logic                    rst_n,
    input  logic                    flush,
    input  pipeline_types::p_reg_t  rrat_state [0:31],

    // Read Port 1 (Issue 0 Source Operand 1)
    input  pipeline_types::p_reg_t  p_src1,
    output pipeline_types::word_t   src1_val,
    output logic                    src1_ready,

    // Read Port 2 (Issue 0 Source Operand 2)
    input  pipeline_types::p_reg_t  p_src2,
    output pipeline_types::word_t   src2_val,
    output logic                    src2_ready,

    // Read Port 3 (Issue 1 Source Operand 1)
    input  pipeline_types::p_reg_t  p_src3,
    output pipeline_types::word_t   src3_val,
    output logic                    src3_ready,

    // Read Port 4 (Issue 1 Source Operand 2)
    input  pipeline_types::p_reg_t  p_src4,
    output pipeline_types::word_t   src4_val,
    output logic                    src4_ready,

    // Allocation Port 0 (Rename Slot 0)
    input  logic                    alloc_en,   // Asserted when allocating p_dest (use_rd == 1)
    input  pipeline_types::p_reg_t  p_dest,     // Newly allocated physical register tag

    // Allocation Port 1 (Rename Slot 1)
    input  logic                    alloc_en1,
    input  pipeline_types::p_reg_t  p_dest1,

    // Writeback Port (Common Data Bus - CDB Broadcast)
    cdb_if.Monitor                  cdb,

    // Readiness Bitmask Output
    output logic [63:0]             p_ready_out
);
    import pipeline_types::*;

    // 64 x 32-bit Physical Register Data Storage
    word_t registers [0:63];

    // 64-bit Readiness Bitmask (1 if valid in PRF, 0 if pending execution)
    logic [63:0] p_ready;
    assign p_ready_out = p_ready;

    // 1. Read Ports with Zero-Latency CDB Bypass Logic
    always_comb begin
        // Read Port 1
        if (p_src1 == 6'd0) begin
            src1_val   = 32'd0;
            src1_ready = 1'b1;
        end else if (cdb.payload.valid && (cdb.payload.p_dest == p_src1)) begin
            src1_val   = cdb.payload.value;
            src1_ready = 1'b1;
        end else begin
            src1_val   = registers[p_src1];
            src1_ready = p_ready[p_src1];
        end

        // Read Port 2
        if (p_src2 == 6'd0) begin
            src2_val   = 32'd0;
            src2_ready = 1'b1;
        end else if (cdb.payload.valid && (cdb.payload.p_dest == p_src2)) begin
            src2_val   = cdb.payload.value;
            src2_ready = 1'b1;
        end else begin
            src2_val   = registers[p_src2];
            src2_ready = p_ready[p_src2];
        end

        // Read Port 3
        if (p_src3 == 6'd0) begin
            src3_val   = 32'd0;
            src3_ready = 1'b1;
        end else if (cdb.payload.valid && (cdb.payload.p_dest == p_src3)) begin
            src3_val   = cdb.payload.value;
            src3_ready = 1'b1;
        end else begin
            src3_val   = registers[p_src3];
            src3_ready = p_ready[p_src3];
        end

        // Read Port 4
        if (p_src4 == 6'd0) begin
            src4_val   = 32'd0;
            src4_ready = 1'b1;
        end else if (cdb.payload.valid && (cdb.payload.p_dest == p_src4)) begin
            src4_val   = cdb.payload.value;
            src4_ready = 1'b1;
        end else begin
            src4_val   = registers[p_src4];
            src4_ready = p_ready[p_src4];
        end
    end

    // 2. Synchronous Write & Readiness Update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Reset State: p0 = 0, p0..p31 ready = 1, p32..p63 ready = 0
            for (int i = 0; i < 64; i++) begin
                registers[i] <= 32'd0;
            end
            p_ready <= 64'h00000000FFFFFFFF; // p0..p31 ready at boot
        end else begin
            // 1. Write result when CDB broadcasts completion (ALWAYS, even during flush!)
            if (cdb.payload.valid && (cdb.payload.p_dest != 6'd0)) begin
                registers[cdb.payload.p_dest] <= cdb.payload.value;
            end

            // 2. Readiness Update: Flush restores from committed RRAT state, else normal tracking
            if (flush) begin
                logic [63:0] flush_ready;
                flush_ready = 64'd1; // p0 is always ready
                for (int a = 0; a < 32; a++) begin
                    flush_ready[rrat_state[a]] = 1'b1;
                end
                if (cdb.payload.valid && (cdb.payload.p_dest != 6'd0)) begin
                    flush_ready[cdb.payload.p_dest] = 1'b1;
                end
                p_ready <= flush_ready;
            end else begin
                // Normal readiness tracking
                logic [63:0] next_ready;
                next_ready = p_ready;

                if (cdb.payload.valid && (cdb.payload.p_dest != 6'd0)) begin
                    next_ready[cdb.payload.p_dest] = 1'b1;
                end
                if (alloc_en && (p_dest != 6'd0)) begin
                    next_ready[p_dest] = 1'b0;
                end
                if (alloc_en1 && (p_dest1 != 6'd0)) begin
                    next_ready[p_dest1] = 1'b0;
                end
                p_ready <= next_ready;
            end
        end
    end
endmodule
