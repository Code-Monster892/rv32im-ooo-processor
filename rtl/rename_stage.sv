// Rename Stage Module (R10K / RSD Paradigm)
// Connects Decode Stage, Free List, RAT, and PRF Readiness to populate rename_dispatch_if.
// Supports 2-Way Superscalar Dual-Rename with Cross-Lane Dependency Forwarding.
module rename_stage (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,

    // Decoupled Inputs from Decode Stage (Slot 0 & Slot 1)
    fetch_decode_if.Slave                 dec_in,
    fetch_decode_if.Slave                 dec_in1,

    // Decoupled Outputs to Dispatch Stage (Slot 0 & Slot 1)
    rename_dispatch_if.Master             disp_out,
    rename_dispatch_if.Master             disp_out1,

    // Release Ports from ROB Retirement Unit
    input  logic                          commit_free_req,
    input  pipeline_types::p_reg_t        commit_free_tag,
    input  logic                          commit_free_req1,
    input  pipeline_types::p_reg_t        commit_free_tag1,

    // Non-Speculative Snapshot from Retirement RAT (for 1-cycle flush recovery)
    input  pipeline_types::p_reg_t        rrat_state [0:31],

    // Readiness Bitmask from PRF
    input  logic [63:0]                   p_ready,

    // Common Data Bus (CDB) Monitor for zero-latency wakeup
    cdb_if.Monitor                        cdb,

    // Output allocation info to PRF
    output logic                          alloc_en0,
    output pipeline_types::p_reg_t        alloc_p_dest0,
    output logic                          alloc_en1,
    output pipeline_types::p_reg_t        alloc_p_dest1,

    // LSQ Index and Type Interfaces
    input  logic [2:0]                    lsq_idx0,
    input  logic [2:0]                    lsq_idx1,
    output logic                          is_load0_out,
    output logic                          is_store0_out,
    output logic                          is_load1_out,
    output logic                          is_store1_out,
    output logic                          free_list_empty_out
);
    import pipeline_types::*;

    // 1. INSTRUCTION DECODE - SLOT 0
    word_t      instr0, pc0;
    a_reg_t     a_rs1_0, a_rs2_0, a_rd_0;
    logic       use_rs1_0, use_rs2_0, use_rd_0;
    exec_unit_t exec_unit0;
    alu_op_t    alu_op0;
    logic [2:0] imm_src0;
    word_t      imm_ext0;
    logic       is_branch0, is_jump0, is_jalr0, is_auipc0;

    assign instr0  = dec_in.data.instr;
    assign pc0     = dec_in.data.pc;
    assign a_rs1_0 = instr0[19:15];
    assign a_rs2_0 = instr0[24:20];
    assign a_rd_0  = instr0[11:7];

    control ctrl_inst0 (
        .op        (instr0[6:0]),
        .funct3    (instr0[14:12]),
        .funct7    (instr0[31:25]),
        .rd        (a_rd_0),
        .use_rs1   (use_rs1_0),
        .use_rs2   (use_rs2_0),
        .use_rd    (use_rd_0),
        .exec_unit (exec_unit0),
        .alu_op    (alu_op0),
        .imm_src   (imm_src0),
        .is_branch (is_branch0),
        .is_jump   (is_jump0),
        .is_jalr   (is_jalr0),
        .is_auipc  (is_auipc0)
    );

    signext sext_inst0 (
        .instr   (instr0),
        .imm_src (imm_src0),
        .imm_ext (imm_ext0)
    );

    // 2. INSTRUCTION DECODE - SLOT 1
    word_t      instr1, pc1;
    a_reg_t     a_rs1_1, a_rs2_1, a_rd_1;
    logic       use_rs1_1, use_rs2_1, use_rd_1;
    exec_unit_t exec_unit1;
    alu_op_t    alu_op1;
    logic [2:0] imm_src1;
    word_t      imm_ext1;
    logic       is_branch1, is_jump1, is_jalr1, is_auipc1;

    assign instr1  = dec_in1.data.instr;
    assign pc1     = dec_in1.data.pc;
    assign a_rs1_1 = instr1[19:15];
    assign a_rs2_1 = instr1[24:20];
    assign a_rd_1  = instr1[11:7];

    control ctrl_inst1 (
        .op        (instr1[6:0]),
        .funct3    (instr1[14:12]),
        .funct7    (instr1[31:25]),
        .rd        (a_rd_1),
        .use_rs1   (use_rs1_1),
        .use_rs2   (use_rs2_1),
        .use_rd    (use_rd_1),
        .exec_unit (exec_unit1),
        .alu_op    (alu_op1),
        .imm_src   (imm_src1),
        .is_branch (is_branch1),
        .is_jump   (is_jump1),
        .is_jalr   (is_jalr1),
        .is_auipc  (is_auipc1)
    );

    signext sext_inst1 (
        .instr   (instr1),
        .imm_src (imm_src1),
        .imm_ext (imm_ext1)
    );

    // 3. FREE LIST ALLOCATION (DUAL-PORTED)
    p_reg_t alloc_tag0, alloc_tag1;
    logic   free_list_empty, free_list_empty1;
    logic   alloc_req0, alloc_req1;

    assign alloc_req0 = dec_in.valid && use_rd_0;
    assign alloc_req1 = dec_in1.valid && use_rd_1 && disp_out.valid && disp_out.ready;

    free_list free_list_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush),
        .rrat_state (rrat_state),

        .alloc_req  (alloc_req0 && disp_out.ready),
        .alloc_tag  (alloc_tag0),
        .empty      (free_list_empty),

        .alloc_req1 (alloc_req1 && disp_out1.ready),
        .alloc_tag1 (alloc_tag1),
        .empty1     (free_list_empty1),

        .free_req   (commit_free_req),
        .free_tag   (commit_free_tag),
        .free_req1  (commit_free_req1),
        .free_tag1  (commit_free_tag1)
    );

    p_reg_t p_dest0, p_dest1;
    assign p_dest0 = use_rd_0 ? alloc_tag0 : 6'd0;
    assign p_dest1 = use_rd_1 ? alloc_tag1 : 6'd0;

    assign alloc_en0     = use_rd_0 && disp_out.ready && dec_in.valid;
    assign alloc_p_dest0 = p_dest0;
    assign alloc_en1     = use_rd_1 && disp_out1.ready && dec_in1.valid && disp_out.valid && disp_out.ready;
    assign alloc_p_dest1 = p_dest1;

    // 4. REGISTER ALIAS TABLE (RAT) - DUAL RENAME
    p_reg_t p_src1_0, p_src2_0, old_p_dest0;
    p_reg_t p_src1_1, p_src2_1, old_p_dest1;

    rat rat_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .flush      (flush),
        .rrat_state (rrat_state),

        // Slot 0
        .a_rs1      (use_rs1_0 ? a_rs1_0 : 5'd0),
        .p_src1     (p_src1_0),
        .a_rs2      (use_rs2_0 ? a_rs2_0 : 5'd0),
        .p_src2     (p_src2_0),
        .use_rd     (use_rd_0 && disp_out.ready && dec_in.valid),
        .a_rd       (a_rd_0),
        .p_dest     (p_dest0),
        .old_p_dest (old_p_dest0),

        // Slot 1 (with cross-lane forwarding from Slot 0)
        .a_rs1_1    (use_rs1_1 ? a_rs1_1 : 5'd0),
        .p_src1_1   (p_src1_1),
        .a_rs2_1    (use_rs2_1 ? a_rs2_1 : 5'd0),
        .p_src2_1   (p_src2_1),
        .use_rd1    (use_rd_1 && disp_out1.ready && dec_in1.valid && disp_out.valid && disp_out.ready),
        .a_rd1      (a_rd_1),
        .p_dest1    (p_dest1),
        .old_p_dest1(old_p_dest1)
    );

    // 5. OPERAND READINESS CHECK (NON-BLOCKING)
    logic src1_ready0, src2_ready0;
    assign src1_ready0 = !use_rs1_0 || (p_src1_0 == 6'd0) || p_ready[p_src1_0] ||
                         (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && cdb.payload.p_dest == p_src1_0);
    assign src2_ready0 = !use_rs2_0 || (p_src2_0 == 6'd0) || p_ready[p_src2_0] ||
                         (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && cdb.payload.p_dest == p_src2_0);

    logic raw_dep_rs1, raw_dep_rs2;
    assign raw_dep_rs1 = use_rs1_1 && use_rd_0 && (a_rd_0 != 5'd0) && (a_rs1_1 == a_rd_0);
    assign raw_dep_rs2 = use_rs2_1 && use_rd_0 && (a_rd_0 != 5'd0) && (a_rs2_1 == a_rd_0);

    logic src1_ready1, src2_ready1;
    assign src1_ready1 = !use_rs1_1 || (!raw_dep_rs1 && ((p_src1_1 == 6'd0) || p_ready[p_src1_1] ||
                         (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && cdb.payload.p_dest == p_src1_1)));
    assign src2_ready1 = !use_rs2_1 || (!raw_dep_rs2 && ((p_src2_1 == 6'd0) || p_ready[p_src2_1] ||
                         (cdb.payload.valid && cdb.payload.p_dest != 6'd0 && cdb.payload.p_dest == p_src2_1)));

    // 6. OUTPUT HANDSHAKING & PAYLOAD DRIVE
    // Non-blocking rename: only depends on dispatch backpressure and free list space
    assign dec_in.ready   = disp_out.ready && (!use_rd_0 || !free_list_empty);
    assign disp_out.valid = dec_in.valid   && (!use_rd_0 || !free_list_empty);

    assign disp_out.data.pc          = pc0;
    assign disp_out.data.exec_unit   = exec_unit0;
    assign disp_out.data.alu_op      = alu_op0;
    assign is_load0_out  = (exec_unit0 == UNIT_LSQ) && (instr0[6:0] == 7'b0000011);
    assign is_store0_out = (exec_unit0 == UNIT_LSQ) && (instr0[6:0] == 7'b0100011);
    assign is_load1_out  = (exec_unit1 == UNIT_LSQ) && (instr1[6:0] == 7'b0000011);
    assign is_store1_out = (exec_unit1 == UNIT_LSQ) && (instr1[6:0] == 7'b0100011);
    assign free_list_empty_out = free_list_empty;

    assign disp_out.data.funct3      = instr0[14:12];
    assign disp_out.data.imm         = imm_ext0;
    assign disp_out.data.p_src1      = use_rs1_0 ? p_src1_0 : 6'd0;
    assign disp_out.data.src1_ready  = src1_ready0;
    assign disp_out.data.p_src2      = use_rs2_0 ? p_src2_0 : 6'd0;
    assign disp_out.data.src2_ready  = src2_ready0;
    assign disp_out.data.p_dest      = p_dest0;
    assign disp_out.data.old_p_dest  = old_p_dest0;
    assign disp_out.data.a_dest      = a_rd_0;
    assign disp_out.data.use_rd      = use_rd_0;
    assign disp_out.data.rob_id      = 6'd0;
    assign disp_out.data.lsq_idx     = lsq_idx0;
    assign disp_out.data.use_rs2     = use_rs2_0;
    assign disp_out.data.is_branch   = is_branch0;
    assign disp_out.data.is_jump     = is_jump0;
    assign disp_out.data.is_jalr     = is_jalr0;
    assign disp_out.data.is_auipc    = is_auipc0;
    assign disp_out.data.pred_taken  = dec_in.data.pred_taken;
    assign disp_out.data.pred_target = dec_in.data.pred_target;
    assign disp_out.data.ghr         = dec_in.data.ghr;

    // Slot 1 Handshaking & Payload
    assign dec_in1.ready   = disp_out1.ready && (!use_rd_1 || !free_list_empty1) && disp_out.valid && disp_out.ready;
    assign disp_out1.valid = dec_in1.valid   && (!use_rd_1 || !free_list_empty1) && disp_out.valid && disp_out.ready;

    assign disp_out1.data.pc          = pc1;
    assign disp_out1.data.exec_unit   = exec_unit1;
    assign disp_out1.data.alu_op      = alu_op1;
    assign disp_out1.data.funct3      = instr1[14:12];
    assign disp_out1.data.imm         = imm_ext1;
    assign disp_out1.data.p_src1      = use_rs1_1 ? p_src1_1 : 6'd0;
    assign disp_out1.data.src1_ready  = src1_ready1;
    assign disp_out1.data.p_src2      = use_rs2_1 ? p_src2_1 : 6'd0;
    assign disp_out1.data.src2_ready  = src2_ready1;
    assign disp_out1.data.p_dest      = p_dest1;
    assign disp_out1.data.old_p_dest  = old_p_dest1;
    assign disp_out1.data.a_dest      = a_rd_1;
    assign disp_out1.data.use_rd      = use_rd_1;
    assign disp_out1.data.rob_id      = 6'd0;
    assign disp_out1.data.lsq_idx     = lsq_idx1;
    assign disp_out1.data.use_rs2     = use_rs2_1;
    assign disp_out1.data.is_branch   = is_branch1;
    assign disp_out1.data.is_jump     = is_jump1;
    assign disp_out1.data.is_jalr     = is_jalr1;
    assign disp_out1.data.is_auipc    = is_auipc1;
    assign disp_out1.data.pred_taken  = dec_in1.data.pred_taken;
    assign disp_out1.data.pred_target = dec_in1.data.pred_target;
    assign disp_out1.data.ghr         = dec_in1.data.ghr;

endmodule
