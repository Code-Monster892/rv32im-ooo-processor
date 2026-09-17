// Reservation Station to Execution Unit Issue Interface
interface issue_if (
    input logic clk,
    input logic rst_n
);
    import pipeline_types::*;

    logic       valid;
    logic       ready;
    logic       flush;
    
    // Issue Payload
    word_t      pc;
    word_t      src1_val;
    word_t      src2_val;
    word_t      imm;
    alu_op_t    alu_op;
    logic [2:0] funct3;
    p_reg_t     p_dest;
    rob_id_t    rob_id;
    logic [2:0] lsq_idx;
    logic       use_rs2;
    logic       is_branch;
    logic       is_jump;
    logic       is_jalr;
    logic       is_auipc;
    logic       pred_taken;
    word_t      pred_target;
    logic [7:0] ghr;

    // Master port (Reservation Station Producer)
    modport Master (
        output valid, pc, src1_val, src2_val, imm, alu_op, funct3, p_dest, rob_id,
               lsq_idx, use_rs2, is_branch, is_jump, is_jalr, is_auipc, pred_taken, pred_target, ghr,
        input  ready, flush
    );

    // Slave port (Execution Unit Consumer)
    modport Slave (
        input  valid, pc, src1_val, src2_val, imm, alu_op, funct3, p_dest, rob_id,
               lsq_idx, use_rs2, is_branch, is_jump, is_jalr, is_auipc, pred_taken, pred_target, ghr,
        output ready,
        input  flush
    );
endinterface
