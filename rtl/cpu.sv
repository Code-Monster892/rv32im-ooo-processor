// 2-Way Superscalar Out-of-Order (OoO) RV32IM Processor (R10K / RSD Paradigm)
// Fully decoupled dynamic execution pipeline with PRF, ROB, RS, LSQ, and CDB.

module cpu (
    input  logic        clk,
    input  logic        rst_n,

    // MMIO Interface
    output logic        mmio_we,
    output logic        mmio_read_en,
    output logic [31:0] mmio_address,
    output logic [31:0] mmio_write_data,
    input  logic [31:0] mmio_read_data,

    // Debug & Verification Interface
    output logic [31:0] pc_out,
    output logic [31:0] debug_id_pc,
    output logic [31:0] debug_id_instr,
    output logic        debug_pc_src_e,
    output logic [31:0] debug_pc_target_e,
    output logic        debug_stall_f,
    output logic        debug_stall_d,
    output logic        debug_flush_e,
    output logic        debug_cdb_valid,
    output logic [5:0]  debug_cdb_tag,
    output logic [31:0] debug_cdb_data,
    output logic [31:0] debug_src_a,
    output logic [31:0] debug_src_b,
    output logic [31:0] debug_alu_result,
    output logic        debug_commit_valid,
    output logic [31:0] debug_commit_pc,
    output logic        debug_sq_empty,
    output logic        debug_rob_full,
    output logic        debug_fl_empty
);

    import pipeline_types::*;

    `ifdef COCOTB_SIM
    initial begin
        $dumpfile("sim_build/waveform.vcd");
        $dumpvars(0, cpu);
    end
    `endif

    // 1. DECOUPLED INFRASTRUCTURE INTERFACES
    fetch_decode_if    fetch_dec_if    (.clk(clk), .rst_n(rst_n));
    fetch_decode_if    fetch_dec_if1   (.clk(clk), .rst_n(rst_n));
    rename_dispatch_if rename_disp_if  (.clk(clk), .rst_n(rst_n));
    rename_dispatch_if rename_disp_if1 (.clk(clk), .rst_n(rst_n));
    issue_if           issue_bus       (.clk(clk), .rst_n(rst_n));
    issue_if           issue_bus1      (.clk(clk), .rst_n(rst_n));
    cdb_if             cdb             (.clk(clk), .rst_n(rst_n));
    rob_commit_if      commit_if       (.clk(clk), .rst_n(rst_n));
    rob_commit_if      commit_if1      (.clk(clk), .rst_n(rst_n));

    // 2. PIPELINE FLUSH & RECOVERY REPLAY LOGIC
    logic        flush;
    logic [31:0] flush_pc;

    assign flush    = commit_if.flush_out || commit_if1.flush_out;
    assign flush_pc = commit_if.flush_out ? commit_if.flush_pc : commit_if1.flush_pc;

    // 3. STAGE 1: SUPERSCALAR INSTRUCTION FETCH (IF)
    logic [31:0] if_pc, next_pc;
    assign pc_out = if_pc;

    logic [31:0] if_instr, if_instr1;
    logic        stall_f, stall_d, stall_slot1_only;

    // Branch Predictor Signals (Slot 0)
    logic        btb_pred_hit;
    logic [31:0] btb_pred_target;
    logic        bht_pred_taken;
    logic [7:0]  curr_ghr;
    logic        ras_pop_valid;
    logic [31:0] ras_pop_addr;

    // Fast call/return detection at Fetch (Slot 0)
    logic is_ret_f;
    assign is_ret_f = (if_instr[6:0] == 7'b1100111) && (if_instr[19:15] == 5'd1) && (if_instr[11:7] == 5'd0);

    logic is_call_f;
    assign is_call_f = ((if_instr[6:0] == 7'b1101111) || (if_instr[6:0] == 7'b1100111)) && (if_instr[11:7] == 5'd1);

    // Dynamic Branch Predictor Decision (Slot 0)
    logic pred_taken_f;
    assign pred_taken_f = (is_ret_f && ras_pop_valid) || (btb_pred_hit && bht_pred_taken);

    logic [31:0] pred_target_f;
    assign pred_target_f = (is_ret_f && ras_pop_valid) ? ras_pop_addr : btb_pred_target;

    // Dual-Fetch Alignment & Validity
    logic fetch_valid0, fetch_valid1;
    assign fetch_valid0 = 1'b1;
    assign fetch_valid1 = (if_pc[2] == 1'b0) && !pred_taken_f;

    // Branch Predictor Signals (Slot 1)
    logic is_jal_f1;
    logic [31:0] jal_target_f1;
    assign is_jal_f1 = (if_instr1[6:0] == 7'b1101111);
    assign jal_target_f1 = (if_pc + 32'd4) + {{12{if_instr1[31]}}, if_instr1[19:12], if_instr1[20], if_instr1[30:21], 1'b0};

    logic is_ret_f1;
    assign is_ret_f1 = (if_instr1[6:0] == 7'b1100111) && (if_instr1[19:15] == 5'd1) && (if_instr1[11:7] == 5'd0);

    logic is_call_f1;
    assign is_call_f1 = ((if_instr1[6:0] == 7'b1101111) || (if_instr1[6:0] == 7'b1100111)) && (if_instr1[11:7] == 5'd1);

    logic        btb_pred_hit1;
    logic [31:0] btb_pred_target1;
    logic        bht_pred_taken1;
    logic        pred_taken_f1;
    logic [31:0] pred_target_f1;

    assign pred_taken_f1 = is_jal_f1 || (is_ret_f1 && ras_pop_valid) || (btb_pred_hit1 && bht_pred_taken1);
    assign pred_target_f1 = is_jal_f1 ? jal_target_f1 :
                            ((is_ret_f1 && ras_pop_valid) ? ras_pop_addr : btb_pred_target1);

    // Next PC Multiplexer
    assign next_pc = flush ? flush_pc :
                     (pred_taken_f ? pred_target_f :
                     ((fetch_valid1 && pred_taken_f1) ? pred_target_f1 :
                     (fetch_valid1 ? (if_pc + 32'd8) : (if_pc + 32'd4))));

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                 if_pc <= 32'd0;
        else if (flush || !stall_f) if_pc <= next_pc;
    end

    // Branch Target Buffer (BTB)
    logic        branch_resolved;
    logic [31:0] branch_pc;
    logic [31:0] branch_actual_target;
    logic        branch_actual_taken;
    logic [7:0]  branch_ghr;
    logic        is_branch_eval;

    btb #(.BTB_ENTRIES(64), .BTB_IDX_BITS(6), .BTB_TAG_BITS(24)) btb_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .fetch_pc      (if_pc),
        .pred_hit      (btb_pred_hit),
        .pred_target   (btb_pred_target),
        .fetch_pc1     (if_pc + 32'd4),
        .pred_hit1     (btb_pred_hit1),
        .pred_target1  (btb_pred_target1),
        .update_en     (branch_resolved && branch_actual_taken),
        .update_pc     (branch_pc),
        .update_target (branch_actual_target)
    );

    // Branch History Table (BHT - GShare)
    bht #(.BHT_ENTRIES(256), .GHR_BITS(8)) bht_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .fetch_pc      (if_pc),
        .pred_taken    (bht_pred_taken),
        .curr_ghr      (curr_ghr),
        .fetch_pc1     (if_pc + 32'd4),
        .pred_taken1   (bht_pred_taken1),
        .update_en     (branch_resolved && is_branch_eval),
        .update_pc     (branch_pc),
        .update_ghr    (branch_ghr),
        .actual_taken  (branch_actual_taken)
    );

    // Return Address Stack (RAS)
    ras #(.RAS_DEPTH(8), .RAS_PTR_BITS(3)) ras_inst (
        .clk           (clk),
        .rst_n         (rst_n),
        .flush         (flush),
        .push_en       (is_call_f && !stall_f),
        .push_addr     (if_pc + 32'd4),
        .pop_en        (is_ret_f && !stall_f),
        .pop_valid     (ras_pop_valid),
        .pop_addr      (ras_pop_addr)
    );

    // 4. MEMORY SUBSYSTEM (Separate Read & Write Ports)
    logic [31:0] ram_read_data;
    logic        ram_we;
    logic [3:0]  ram_mask;
    logic [31:0] ram_addr, ram_wdata;
    logic [31:0] lq_mem_read_addr;

    memory mem_inst (
        .clk          (clk),
        .rst_n        (rst_n),
        .we           (ram_we),
        .mask         (ram_mask),
        .address      (ram_addr),
        .write_data   (ram_wdata),
        .read_address (lq_mem_read_addr),
        .read_data    (ram_read_data),
        .pc_address   (if_pc),
        .instruction  (if_instr),
        .instruction1 (if_instr1)
    );

    // 5. IF/ID PIPELINE REGISTER (Supports Slot 1 Shift on Single Dispatch)
    logic        id_valid0, id_valid1;
    logic [31:0] id_pc0, id_pc1;
    logic [31:0] id_instr0, id_instr1;
    logic        id_pred_taken0, id_pred_taken1;
    logic [31:0] id_pred_target0, id_pred_target1;
    logic [7:0]  id_ghr0, id_ghr1;
    logic [31:0] id_pc, id_instr;

    if_id_reg if_id_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .clear            (flush),
        .en               (!stall_d),
        .stall_slot1_only (stall_slot1_only),

        // Slot 0
        .if_valid0        (fetch_valid0),
        .if_pc0           (if_pc),
        .if_instr0        (if_instr),
        .if_pred_taken0   (pred_taken_f),
        .if_pred_target0  (pred_target_f),
        .if_ghr0          (curr_ghr),

        .id_valid0        (id_valid0),
        .id_pc0           (id_pc0),
        .id_instr0        (id_instr0),
        .id_pred_taken0   (id_pred_taken0),
        .id_pred_target0  (id_pred_target0),
        .id_ghr0          (id_ghr0),

        // Slot 1
        .if_valid1        (fetch_valid1),
        .if_pc1           (if_pc + 32'd4),
        .if_instr1        (if_instr1),
        .if_pred_taken1   (fetch_valid1 && pred_taken_f1),
        .if_pred_target1  (pred_target_f1),
        .if_ghr1          (curr_ghr),

        .id_valid1        (id_valid1),
        .id_pc1           (id_pc1),
        .id_instr1        (id_instr1),
        .id_pred_taken1   (id_pred_taken1),
        .id_pred_target1  (id_pred_target1),
        .id_ghr1          (id_ghr1),

        .id_pc            (id_pc),
        .id_instr         (id_instr)
    );

    // 6. STAGE 2: DECODE & RENAME INTERFACES
    assign fetch_dec_if.valid         = id_valid0 && !flush;
    assign fetch_dec_if.data.pc       = id_pc0;
    assign fetch_dec_if.data.instr    = id_instr0;
    assign fetch_dec_if.data.pred_taken  = id_pred_taken0;
    assign fetch_dec_if.data.pred_target = id_pred_target0;
    assign fetch_dec_if.data.ghr         = id_ghr0;
    assign fetch_dec_if.flush         = flush;

    assign fetch_dec_if1.valid        = id_valid1 && !flush;
    assign fetch_dec_if1.data.pc      = id_pc1;
    assign fetch_dec_if1.data.instr   = id_instr1;
    assign fetch_dec_if1.data.pred_taken  = id_pred_taken1;
    assign fetch_dec_if1.data.pred_target = id_pred_target1;
    assign fetch_dec_if1.data.ghr         = id_ghr1;
    assign fetch_dec_if1.flush        = flush;

    // Retirement RAT (RRAT) Instance
    p_reg_t rrat_state [0:31];
    rrat rrat_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .commit_in  (commit_if),
        .commit_in1 (commit_if1),
        .rrat_state (rrat_state)
    );

    // PRF & Rename Subsystems
    logic [63:0] prf_p_ready;
    logic        rn_alloc_en0, rn_alloc_en1;
    p_reg_t      rn_alloc_p_dest0, rn_alloc_p_dest1;
    logic [2:0]  rn_lsq_idx0, rn_lsq_idx1;
    logic        rn_is_load0, rn_is_store0, rn_is_load1, rn_is_store1;
    logic        free_list_empty;

    logic        commit_free_req0, commit_free_req1;
    p_reg_t      commit_free_tag0, commit_free_tag1;

    rename_stage rename_inst (
        .clk                 (clk),
        .rst_n               (rst_n),
        .flush               (flush),
        .dec_in              (fetch_dec_if),
        .dec_in1             (fetch_dec_if1),
        .disp_out            (rename_disp_if),
        .disp_out1           (rename_disp_if1),
        .commit_free_req     (commit_free_req0),
        .commit_free_tag     (commit_free_tag0),
        .commit_free_req1    (commit_free_req1),
        .commit_free_tag1    (commit_free_tag1),
        .rrat_state          (rrat_state),
        .p_ready             (prf_p_ready),
        .cdb                 (cdb),
        .alloc_en0           (rn_alloc_en0),
        .alloc_p_dest0       (rn_alloc_p_dest0),
        .alloc_en1           (rn_alloc_en1),
        .alloc_p_dest1       (rn_alloc_p_dest1),
        .lsq_idx0            (rn_lsq_idx0),
        .lsq_idx1            (rn_lsq_idx1),
        .is_load0_out        (rn_is_load0),
        .is_store0_out       (rn_is_store0),
        .is_load1_out        (rn_is_load1),
        .is_store1_out       (rn_is_store1),
        .free_list_empty_out (free_list_empty)
    );

    // Physical Register File (PRF) - 4 Read Ports + Zero-Latency CDB Bypass
    p_reg_t rs_p_src1, rs_p_src2, rs_p_src3, rs_p_src4;
    word_t  rs_src1_val, rs_src2_val, rs_src3_val, rs_src4_val;
    logic   rs_src1_ready, rs_src2_ready, rs_src3_ready, rs_src4_ready;

    prf prf_inst (
        .clk         (clk),
        .rst_n       (rst_n),
        .flush       (flush),
        .rrat_state  (rrat_state),
        .p_src1      (rs_p_src1),
        .src1_val    (rs_src1_val),
        .src1_ready  (rs_src1_ready),
        .p_src2      (rs_p_src2),
        .src2_val    (rs_src2_val),
        .src2_ready  (rs_src2_ready),
        .p_src3      (rs_p_src3),
        .src3_val    (rs_src3_val),
        .src3_ready  (rs_src3_ready),
        .p_src4      (rs_p_src4),
        .src4_val    (rs_src4_val),
        .src4_ready  (rs_src4_ready),
        .alloc_en    (rn_alloc_en0),
        .p_dest      (rn_alloc_p_dest0),
        .alloc_en1   (rn_alloc_en1),
        .p_dest1     (rn_alloc_p_dest1),
        .cdb         (cdb),
        .p_ready_out (prf_p_ready)
    );

    // 7. QUEUE ALLOCATION & DISPATCH BACKPRESSURE
    logic       rob_full, rob_full1, rob_empty;
    logic       rs_full, rs_full1;
    logic       sq_full, sq_empty;
    logic       lq_full, lq_empty;
    logic [2:0] alloc_sq_idx, alloc_lq_idx;

    assign rn_lsq_idx0 = rn_is_store0 ? alloc_sq_idx : (rn_is_load0 ? alloc_lq_idx : 3'd0);
    assign rn_lsq_idx1 = rn_is_store1 ? alloc_sq_idx : (rn_is_load1 ? alloc_lq_idx : 3'd0);

    // Dispatch Firing Validation
    logic disp0_req, disp1_req;
    assign disp0_req = rename_disp_if.valid;
    assign disp1_req = rename_disp_if1.valid;

    logic disp0_can_fire;
    assign disp0_can_fire = !rob_full && !rs_full &&
                            !(rn_is_store0 && sq_full) &&
                            !(rn_is_load0 && lq_full);

    logic disp1_can_fire;
    assign disp1_can_fire = disp0_req && disp0_can_fire && !rob_full1 && !rs_full1 &&
                            !(rn_is_store1 && (sq_full || rn_is_store0)) &&
                            !(rn_is_load1 && (lq_full || rn_is_load0));

    assign rename_disp_if.ready  = disp0_can_fire;
    assign rename_disp_if1.ready = disp1_can_fire;

    logic disp0_fire, disp1_fire;
    assign disp0_fire = disp0_req && disp0_can_fire;
    assign disp1_fire = disp1_req && disp1_can_fire;

    assign stall_slot1_only = disp0_fire && id_valid1 && !disp1_fire;
    assign stall_d          = !fetch_dec_if.ready;
    assign stall_f          = stall_d || stall_slot1_only;

    // 8. REORDER BUFFER (ROB) INSTANCE
    rob_id_t alloc_rob_id0, alloc_rob_id1;
    logic    commit_is_store0, commit_is_store1;
    logic    non_cdb_complete_valid;
    rob_id_t non_cdb_complete_rob_id;
    logic    branch_complete_valid;
    rob_id_t branch_complete_rob_id;
    logic    branch_mispredicted;
    word_t   branch_correct_target;
    logic [4:0] rob_head_ptr;

    rob #(.ROB_ENTRIES(32), .ROB_IDX_BITS(5)) rob_inst (
        .clk                     (clk),
        .rst_n                   (rst_n),
        .flush                   (flush),
        .alloc_req               (disp0_fire),
        .alloc_pc                (rename_disp_if.data.pc),
        .alloc_a_dest            (rename_disp_if.data.a_dest),
        .alloc_p_dest            (rename_disp_if.data.p_dest),
        .alloc_old_p_dest        (rename_disp_if.data.old_p_dest),
        .alloc_use_rd            (rename_disp_if.data.use_rd),
        .alloc_is_store          (rn_is_store0),
        .alloc_rob_id            (alloc_rob_id0),
        .full                    (rob_full),

        .alloc_req1              (disp1_fire),
        .alloc_pc1               (rename_disp_if1.data.pc),
        .alloc_a_dest1           (rename_disp_if1.data.a_dest),
        .alloc_p_dest1           (rename_disp_if1.data.p_dest),
        .alloc_old_p_dest1       (rename_disp_if1.data.old_p_dest),
        .alloc_use_rd1           (rename_disp_if1.data.use_rd),
        .alloc_is_store1         (rn_is_store1),
        .alloc_rob_id1           (alloc_rob_id1),
        .full1                   (rob_full1),

        .cdb                     (cdb),

        .commit_out              (commit_if),
        .commit_free_req         (commit_free_req0),
        .commit_free_tag         (commit_free_tag0),
        .commit_is_store         (commit_is_store0),

        .commit_out1             (commit_if1),
        .commit_free_req1        (commit_free_req1),
        .commit_free_tag1        (commit_free_tag1),
        .commit_is_store1        (commit_is_store1),

        .empty                   (rob_empty),

        .non_cdb_complete_valid  (non_cdb_complete_valid),
        .non_cdb_complete_rob_id (non_cdb_complete_rob_id),

        .branch_complete_valid   (branch_complete_valid),
        .branch_complete_rob_id  (branch_complete_rob_id),
        .branch_mispredicted     (branch_mispredicted),
        .branch_correct_target   (branch_correct_target),

        .rob_head_ptr            (rob_head_ptr)
    );

    // 9. UNIFIED RESERVATION STATION (RS) INSTANCE
    exec_unit_t issue_exec_unit0, issue_exec_unit1;

    reservation_station rs_inst (
        .clk              (clk),
        .rst_n            (rst_n),
        .flush            (flush),

        .alloc_req0       (disp0_fire),
        .disp_in          (rename_disp_if),
        .alloc_rob_id     (alloc_rob_id0),
        .full             (rs_full),

        .alloc_req1       (disp1_fire),
        .disp_in1         (rename_disp_if1),
        .alloc_rob_id1    (alloc_rob_id1),
        .full1            (rs_full1),

        .cdb              (cdb),

        .issue_p_src1     (rs_p_src1),
        .issue_src1_val   (rs_src1_val),
        .issue_p_src2     (rs_p_src2),
        .issue_src2_val   (rs_src2_val),

        .issue_p_src3     (rs_p_src3),
        .issue_src3_val   (rs_src3_val),
        .issue_p_src4     (rs_p_src4),
        .issue_src4_val   (rs_src4_val),

        .issue_out        (issue_bus),
        .issue_exec_unit  (issue_exec_unit0),

        .issue_out1       (issue_bus1),
        .issue_exec_unit1 (issue_exec_unit1)
    );

    // 10. STORE QUEUE & LOAD QUEUE SUBSYSTEM
    logic        sq_alloc_req;
    rob_id_t     sq_alloc_rob_id;
    assign sq_alloc_req    = (disp0_fire && rn_is_store0) || (disp1_fire && rn_is_store1 && !rn_is_store0);
    assign sq_alloc_rob_id = (disp0_fire && rn_is_store0) ? alloc_rob_id0 : alloc_rob_id1;

    logic        lq_alloc_req;
    rob_id_t     lq_alloc_rob_id;
    p_reg_t      lq_alloc_p_dest;
    logic [2:0]  lq_alloc_funct3;
    assign lq_alloc_req    = (disp0_fire && rn_is_load0) || (disp1_fire && rn_is_load1 && !rn_is_load0);
    assign lq_alloc_rob_id = (disp0_fire && rn_is_load0) ? alloc_rob_id0 : alloc_rob_id1;
    assign lq_alloc_p_dest = (disp0_fire && rn_is_load0) ? rename_disp_if.data.p_dest : rename_disp_if1.data.p_dest;
    assign lq_alloc_funct3 = (disp0_fire && rn_is_load0) ? rename_disp_if.data.funct3 : rename_disp_if1.data.funct3;

    // AGU Signal Extraction from Issue Port 0
    logic        agu_is_store, agu_is_load;
    logic [31:0] agu_addr;
    logic        sq_fill_addr_valid, sq_fill_data_valid, lq_exec_addr_valid;
    logic [3:0]  sq_be_mask;
    logic [31:0] sq_shifted_data;

    assign agu_is_store = issue_bus.valid && issue_bus.ready && (issue_exec_unit0 == UNIT_LSQ) && issue_bus.use_rs2;
    assign agu_is_load  = issue_bus.valid && issue_bus.ready && (issue_exec_unit0 == UNIT_LSQ) && !issue_bus.use_rs2;
    assign agu_addr     = issue_bus.src1_val + issue_bus.imm;

    assign sq_fill_addr_valid = agu_is_store;
    assign sq_fill_data_valid = agu_is_store;
    assign lq_exec_addr_valid = agu_is_load;

    be be_inst (
        .funct3       (issue_bus.funct3),
        .offset       (agu_addr[1:0]),
        .write_data   (issue_bus.src2_val),
        .mask         (sq_be_mask),
        .shifted_data (sq_shifted_data)
    );

    // Store Queue (SQ) Instance
    logic        sq_lq_fwd_hit;
    word_t       sq_lq_fwd_data;
    logic [3:0]  sq_lq_fwd_mask;
    word_t       lq_sq_query_addr;
    rob_id_t     lq_sq_query_rob_id;
    logic        sq_lq_fwd_hazard;
    logic        sq_mem_we;
    logic [3:0]  sq_mem_mask;
    word_t       sq_mem_address, sq_mem_write_data;

    store_queue #(.SQ_ENTRIES(8)) sq_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush),
        .alloc_req       (sq_alloc_req),
        .alloc_rob_id    (sq_alloc_rob_id),
        .alloc_sq_idx    (alloc_sq_idx),
        .full            (sq_full),
        .fill_addr_valid (sq_fill_addr_valid),
        .fill_sq_idx     (issue_bus.lsq_idx),
        .fill_address    (agu_addr),
        .fill_mask       (sq_be_mask),
        .fill_data_valid (sq_fill_data_valid),
        .fill_data       (sq_shifted_data),
        .fwd_query_addr  (lq_sq_query_addr),
        .fwd_query_rob_id(lq_sq_query_rob_id),
        .rob_head_ptr    (rob_head_ptr),
        .fwd_hit         (sq_lq_fwd_hit),
        .fwd_data        (sq_lq_fwd_data),
        .fwd_mask        (sq_lq_fwd_mask),
        .fwd_hazard      (sq_lq_fwd_hazard),
        .commit_req      (commit_if.payload.valid && commit_is_store0),
        .commit_rob_id   (commit_if.payload.rob_id),
        .mem_we          (sq_mem_we),
        .mem_mask        (sq_mem_mask),
        .mem_address     (sq_mem_address),
        .mem_write_data  (sq_mem_write_data),
        .empty           (sq_empty)
    );

    // Load Queue (LQ) Instance
    logic        lq_mem_read_en;
    word_t       lq_mem_read_data;
    logic        lq_wb_valid;
    p_reg_t      lq_wb_p_dest;
    word_t       lq_wb_data;
    rob_id_t     lq_wb_rob_id;
    logic        lq_wb_ready;

    load_queue #(.LQ_ENTRIES(8)) lq_inst (
        .clk             (clk),
        .rst_n           (rst_n),
        .flush           (flush),
        .alloc_req       (lq_alloc_req),
        .alloc_rob_id    (lq_alloc_rob_id),
        .alloc_p_dest    (lq_alloc_p_dest),
        .alloc_funct3    (lq_alloc_funct3),
        .alloc_lq_idx    (alloc_lq_idx),
        .full            (lq_full),
        .exec_addr_valid (lq_exec_addr_valid),
        .exec_lq_idx     (issue_bus.lsq_idx),
        .exec_address    (agu_addr),
        .sq_query_addr   (lq_sq_query_addr),
        .sq_query_rob_id (lq_sq_query_rob_id),
        .sq_fwd_hit      (sq_lq_fwd_hit),
        .sq_fwd_data     (sq_lq_fwd_data),
        .sq_fwd_mask     (sq_lq_fwd_mask),
        .sq_fwd_hazard   (sq_lq_fwd_hazard),
        .mem_read_en     (lq_mem_read_en),
        .mem_read_addr   (lq_mem_read_addr),
        .mem_read_data   (lq_mem_read_data),
        .wb_valid        (lq_wb_valid),
        .wb_p_dest       (lq_wb_p_dest),
        .wb_data         (lq_wb_data),
        .wb_rob_id       (lq_wb_rob_id),
        .wb_ready        (lq_wb_ready),
        .empty           (lq_empty)
    );

    // Memory & MMIO Write Routing: Stores drain STRICTLY at ROB Commit!
    assign ram_we          = sq_mem_we && (sq_mem_address < 32'h01000000);
    assign ram_mask        = sq_mem_mask;
    assign ram_addr        = sq_mem_address;
    assign ram_wdata       = sq_mem_write_data;

    assign mmio_we         = sq_mem_we && (sq_mem_address >= 32'h01000000);
    assign mmio_read_en    = lq_mem_read_en && (lq_mem_read_addr >= 32'h01000000);
    assign mmio_address    = (sq_mem_we && sq_mem_address >= 32'h01000000) ? sq_mem_address : lq_mem_read_addr;
    assign mmio_write_data = sq_mem_write_data;

    // Multiplex load read data between RAM and MMIO
    assign lq_mem_read_data = (lq_mem_read_addr >= 32'h01000000) ? mmio_read_data : ram_read_data;

    // 11. EXECUTION UNITS: ALU0, MULTIPLIER, ALU1, BRANCH EVALUATION
    function automatic logic [3:0] map_alu_control(input alu_op_t op);
        case (op)
            ALU_ADD:  return 4'b0000;
            ALU_SUB:  return 4'b1000;
            ALU_AND:  return 4'b0111;
            ALU_OR:   return 4'b0110;
            ALU_XOR:  return 4'b0100;
            ALU_SLT:  return 4'b0010;
            ALU_SLTU: return 4'b0011;
            ALU_SLL:  return 4'b0001;
            ALU_SRL:  return 4'b0101;
            ALU_SRA:  return 4'b1101;
            default:  return 4'b0000;
        endcase
    endfunction

    // Execution Unit 1: ALU0 (Issue Port 0)
    logic [31:0] alu0_src1, alu0_src2;
    assign alu0_src1 = issue_bus.is_auipc ? issue_bus.pc : issue_bus.src1_val;
    assign alu0_src2 = issue_bus.use_rs2  ? issue_bus.src2_val : issue_bus.imm;

    logic [31:0] alu0_raw_result;
    alu alu_inst0 (
        .src1        (alu0_src1),
        .src2        (alu0_src2),
        .alu_control (map_alu_control(issue_bus.alu_op)),
        .alu_result  (alu0_raw_result),
        .zero        ()
    );

    logic [31:0] alu0_final_result;
    assign alu0_final_result = (issue_bus.is_jump || issue_bus.is_jalr) ? (issue_bus.pc + 32'd4) : alu0_raw_result;

    // Execution Unit 2: Multiplier (Issue Port 0)
    logic [31:0] mul_result;
    multiplier mul_inst (
        .src1       (issue_bus.src1_val),
        .src2       (alu0_src2),
        .funct3     (issue_bus.funct3),
        .mul_result (mul_result)
    );

    // Execution Unit 3: Second ALU - ALU1 (Issue Port 1)
    logic [31:0] alu1_src1, alu1_src2;
    assign alu1_src1 = issue_bus1.is_auipc ? issue_bus1.pc : issue_bus1.src1_val;
    assign alu1_src2 = issue_bus1.use_rs2  ? issue_bus1.src2_val : issue_bus1.imm;

    logic [31:0] alu1_result;
    alu alu_inst1 (
        .src1        (alu1_src1),
        .src2        (alu1_src2),
        .alu_control (map_alu_control(issue_bus1.alu_op)),
        .alu_result  (alu1_result),
        .zero        ()
    );

    // Branch Evaluator (Issue Port 0)
    logic branch_take;
    always_comb begin
        case (issue_bus.funct3)
            3'b000:  branch_take = (issue_bus.src1_val == issue_bus.src2_val);
            3'b001:  branch_take = (issue_bus.src1_val != issue_bus.src2_val);
            3'b100:  branch_take = ($signed(issue_bus.src1_val) < $signed(issue_bus.src2_val));
            3'b101:  branch_take = ($signed(issue_bus.src1_val) >= $signed(issue_bus.src2_val));
            3'b110:  branch_take = (issue_bus.src1_val < issue_bus.src2_val);
            3'b111:  branch_take = (issue_bus.src1_val >= issue_bus.src2_val);
            default: branch_take = 1'b0;
        endcase
    end

    logic is_branch_instr, is_jump_instr, is_jalr_instr, is_ctrl_flow;
    assign is_branch_instr = issue_bus.valid && issue_bus.is_branch;
    assign is_jump_instr   = issue_bus.valid && issue_bus.is_jump;
    assign is_jalr_instr   = issue_bus.valid && issue_bus.is_jalr;
    assign is_ctrl_flow    = is_branch_instr || is_jump_instr || is_jalr_instr;

    logic [31:0] branch_target_taken;
    assign branch_target_taken = is_jalr_instr ? ((issue_bus.src1_val + issue_bus.imm) & 32'hFFFFFFFE)
                                               : (issue_bus.pc + issue_bus.imm);

    assign branch_actual_target = (is_branch_instr && !branch_take) ? (issue_bus.pc + 32'd4) : branch_target_taken;
    assign branch_actual_taken  = is_branch_instr ? branch_take : 1'b1;

    logic is_mispred;
    assign is_mispred = is_branch_instr ? ((issue_bus.pred_taken != branch_take) || (branch_take && (issue_bus.pred_target != branch_target_taken)))
                      : (is_jump_instr || is_jalr_instr) ? ((!issue_bus.pred_taken) || (issue_bus.pred_target != branch_target_taken))
                      : 1'b0;

    assign branch_complete_valid  = is_ctrl_flow && issue_bus.ready;
    assign branch_complete_rob_id = issue_bus.rob_id;
    assign branch_mispredicted    = is_mispred;
    assign branch_correct_target  = branch_actual_target;

    // Branch Predictor Training Wires
    assign branch_resolved = is_ctrl_flow && issue_bus.ready;
    assign branch_pc       = issue_bus.pc;
    assign branch_ghr      = issue_bus.ghr;
    assign is_branch_eval  = is_branch_instr;

    // Non-CDB Completions (Stores)
    assign non_cdb_complete_valid  = agu_is_store;
    assign non_cdb_complete_rob_id = issue_bus.rob_id;

    // 12. COMMON DATA BUS (CDB) ARBITRATION
    logic alu0_cdb_req, mul_cdb_req, alu1_cdb_req;
    assign alu0_cdb_req = issue_bus.valid &&
                          ((issue_exec_unit0 == UNIT_ALU) || ((issue_bus.is_jump || issue_bus.is_jalr) && (issue_bus.p_dest != 6'd0)));
    assign mul_cdb_req  = issue_bus.valid && (issue_exec_unit0 == UNIT_MUL);
    assign alu1_cdb_req = issue_bus1.valid && (issue_exec_unit1 == UNIT_ALU);

    logic alu_grant, mul_grant, mem_grant, alu1_grant;

    cdb_arbiter cdb_arb_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush),

        .alu_valid  (alu0_cdb_req),
        .alu_p_dest (issue_bus.p_dest),
        .alu_value  (alu0_final_result),
        .alu_rob_id (issue_bus.rob_id),
        .alu_ready  (alu_grant),

        .mul_valid  (mul_cdb_req),
        .mul_p_dest (issue_bus.p_dest),
        .mul_value  (mul_result),
        .mul_rob_id (issue_bus.rob_id),
        .mul_ready  (mul_grant),

        .mem_valid  (lq_wb_valid),
        .mem_p_dest (lq_wb_p_dest),
        .mem_value  (lq_wb_data),
        .mem_rob_id (lq_wb_rob_id),
        .mem_ready  (mem_grant),

        .alu1_valid (alu1_cdb_req),
        .alu1_p_dest(issue_bus1.p_dest),
        .alu1_value (alu1_result),
        .alu1_rob_id(issue_bus1.rob_id),
        .alu1_ready (alu1_grant),

        .cdb_out    (cdb)
    );

    assign lq_wb_ready = mem_grant;

    // Issue Bus Handshake Controls
    assign issue_bus.ready = (issue_exec_unit0 == UNIT_MUL) ? mul_grant :
                             ((issue_exec_unit0 == UNIT_ALU || ((issue_bus.is_jump || issue_bus.is_jalr) && (issue_bus.p_dest != 6'd0))) ? alu_grant : 1'b1);
    assign issue_bus.flush = flush;

    assign issue_bus1.ready = (issue_exec_unit1 == UNIT_ALU) ? alu1_grant : 1'b1;
    assign issue_bus1.flush = flush;

    // 13. DEBUG VISIBILITY SIGNALS
    assign debug_id_pc        = id_pc;
    assign debug_id_instr     = id_instr;
    assign debug_pc_src_e     = flush;
    assign debug_pc_target_e  = flush_pc;
    assign debug_stall_f      = stall_f;
    assign debug_stall_d      = stall_d;
    assign debug_flush_e      = flush;
    assign debug_cdb_valid    = cdb.payload.valid;
    assign debug_cdb_tag      = cdb.payload.p_dest;
    assign debug_cdb_data     = cdb.payload.value;
    assign debug_src_a        = issue_bus.src1_val;
    assign debug_src_b        = issue_bus.src2_val;
    assign debug_alu_result   = alu0_final_result;
    assign debug_commit_valid = commit_if.payload.valid;
    assign debug_commit_pc    = commit_if.payload.valid ? commit_if.payload.pc : (commit_if1.payload.valid ? commit_if1.payload.pc : 32'd0);
    assign debug_sq_empty     = sq_empty;
    assign debug_rob_full     = rob_full;
    assign debug_fl_empty     = free_list_empty;

endmodule
