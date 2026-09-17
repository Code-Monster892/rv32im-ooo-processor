// SystemVerilog Package for Out-of-Order PRF (R10K/RSD Style) RISC-V CPU Structs
package pipeline_types;

    // 1. Primitive Microarchitectural Types & Constants
    typedef logic [31:0] word_t;        // 32-bit data word / address
    typedef logic [4:0]  a_reg_t;       // 5-bit Architectural Register Index (x0..x31)
    typedef logic [5:0]  p_reg_t;       // 6-bit Physical Register Index (p0..p63)
    typedef logic [5:0]  rob_id_t;      // 6-bit Reorder Buffer Entry Index (64 entries)

    // Execution Unit Allocation Target
    typedef enum logic [1:0] {
        UNIT_ALU    = 2'b00,            // Standard ALU (add, sub, logic, shift)
        UNIT_MUL    = 2'b01,            // Hardware Multiplier / Divider
        UNIT_LSQ    = 2'b10,            // Load / Store Queue
        UNIT_BRANCH = 2'b11             // Branch / Jump Resolution Unit
    } exec_unit_t;

    // ALU Operation Codes
    typedef enum logic [3:0] {
        ALU_ADD  = 4'b0000,
        ALU_SUB  = 4'b0001,
        ALU_AND  = 4'b0010,
        ALU_OR   = 4'b0011,
        ALU_XOR  = 4'b0100,
        ALU_SLT  = 4'b0101,
        ALU_SLTU = 4'b0110,
        ALU_SLL  = 4'b0111,
        ALU_SRL  = 4'b1000,
        ALU_SRA  = 4'b1001
    } alu_op_t;

    // 2. Decoupled Interface Payloads

    // Fetch -> Decode Transaction Payload
    typedef struct packed {
        word_t      pc;
        word_t      instr;
        logic       pred_taken;
        word_t      pred_target;
        logic [7:0] ghr;
    } fetch_payload_t;

    // 2-Way Superscalar Fetch -> Decode Dual Transaction Payload
    typedef struct packed {
        logic  valid0;
        word_t pc0;
        word_t instr0;

        logic  valid1;
        word_t pc1;
        word_t instr1;
    } fetch_dual_payload_t;

    // Decode -> Rename Transaction Payload
    typedef struct packed {
        word_t      pc;
        word_t      instr;
        a_reg_t     a_rs1;
        logic       use_rs1;
        a_reg_t     a_rs2;
        logic       use_rs2;
        a_reg_t     a_rd;
        logic       use_rd;
        word_t      imm;
        exec_unit_t exec_unit;
        alu_op_t    alu_op;
        logic [2:0] funct3;
        logic       is_branch;
        logic       is_jump;
        logic       is_jalr;
        logic       is_auipc;
    } decode_payload_t;

    // Rename -> Dispatch (RS + ROB) Transaction Payload
    typedef struct packed {
        word_t      pc;
        exec_unit_t exec_unit;
        alu_op_t    alu_op;
        logic [2:0] funct3;
        word_t      imm;
        
        // Physical Register Rename Tags (R10K Paradigm)
        p_reg_t     p_src1;
        logic       src1_ready;         // 1 if operand 1 is already valid in PRF
        p_reg_t     p_src2;
        logic       src2_ready;         // 1 if operand 2 is already valid in PRF
        p_reg_t     p_dest;             // Newly allocated physical register
        p_reg_t     old_p_dest;         // Previously mapped physical register tag for ARF dest
        a_reg_t     a_dest;             // Architectural destination register tag (x0..x31)
        logic       use_rd;             // 1 if instruction writes back to register
        rob_id_t    rob_id;             // Allocated ROB entry tag
        logic [2:0] lsq_idx;            // Allocated LQ or SQ index
        logic       use_rs2;
        logic       is_branch;
        logic       is_jump;
        logic       is_jalr;
        logic       is_auipc;
        logic       pred_taken;
        word_t      pred_target;
        logic [7:0] ghr;
    } rename_payload_t;

    // Common Data Bus (CDB) Broadcast Payload
    typedef struct packed {
        logic    valid;
        p_reg_t  p_dest;
        word_t   value;
        rob_id_t rob_id;
    } cdb_payload_t;

    // ROB -> Retirement / Commit Payload
    typedef struct packed {
        logic    valid;
        word_t   pc;
        a_reg_t  a_dest;
        p_reg_t  p_dest;
        p_reg_t  old_p_dest;
        logic    use_rd;
        rob_id_t rob_id;
    } rob_commit_payload_t;

    // 3. Backward-Compatibility Structs for In-Order Pipeline Transition
    typedef struct packed {
        word_t      pc;
        word_t      reg_data1;
        word_t      reg_data2;
        word_t      imm_ext;
        a_reg_t     rs1;
        a_reg_t     rs2;
        a_reg_t     rd;
        logic [2:0] funct3;
        logic       reg_write;
        logic       mem_write;
        logic       alu_src;
        logic [2:0] result_src;
        logic [3:0] alu_control;
        logic       branch;
        logic       jump;
        logic       jalr;
    } id_ex_reg_t;

    typedef struct packed {
        word_t      alu_result;
        word_t      mul_result;
        word_t      write_data;
        word_t      pc_target;
        word_t      pc_plus4;
        word_t      imm_ext;
        a_reg_t     rd;
        logic [2:0] funct3;
        logic       reg_write;
        logic       mem_write;
        logic [2:0] result_src;
    } ex_mem_reg_t;

    typedef struct packed {
        word_t      alu_result;
        word_t      mul_result;
        word_t      final_read_data;
        word_t      pc_target;
        word_t      pc_plus4;
        word_t      imm_ext;
        a_reg_t     rd;
        logic       reg_write;
        logic [2:0] result_src;
    } mem_wb_reg_t;

endpackage

