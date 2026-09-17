// Out-of-Order Control Decoder Module (R10K / RSD Style)
module control (
    input  logic [6:0]                  op,
    input  logic [2:0]                  funct3,
    input  logic [6:0]                  funct7,
    input  logic [4:0]                  rd,           // Destination architectural register
    output logic                        use_rs1,      // 1 if instruction reads rs1
    output logic                        use_rs2,      // 1 if instruction reads rs2
    output logic                        use_rd,       // 1 if instruction writes rd (and rd != x0)
    output pipeline_types::exec_unit_t  exec_unit,    // Target execution unit
    output pipeline_types::alu_op_t     alu_op,       // ALU operation code
    output logic [2:0]                  imm_src,      // Immediate format selector
    output logic                        is_branch,    // Conditional branch
    output logic                        is_jump,      // JAL jump
    output logic                        is_jalr,      // JALR jump
    output logic                        is_auipc      // AUIPC instruction
);
    import pipeline_types::*;

    always_comb begin
        // Default safe signal values
        use_rs1   = 1'b0;
        use_rs2   = 1'b0;
        use_rd    = 1'b0;
        exec_unit = UNIT_ALU;
        alu_op    = ALU_ADD;
        imm_src   = 3'b000;
        is_branch = 1'b0;
        is_jump   = 1'b0;
        is_jalr   = 1'b0;
        is_auipc  = 1'b0;

        case (op)
            // 1. Loads (I-Type) e.g., LW, LB, LH, LBU, LHU
            7'b0000011: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000);
                exec_unit = UNIT_LSQ;
                imm_src   = 3'b000; // I-type immediate
                alu_op    = ALU_ADD; // Address calculation: base + offset
            end

            // 2. Stores (S-Type) e.g., SW, SB, SH
            7'b0100011: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b1;
                use_rd    = 1'b0;   // Stores do NOT write to a destination register
                exec_unit = UNIT_LSQ;
                imm_src   = 3'b001; // S-type immediate
                alu_op    = ALU_ADD; // Address calculation: base + offset
            end

            // 3. Branches (B-Type) e.g., BEQ, BNE, BLT, BGE
            7'b1100011: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b1;
                use_rd    = 1'b0;
                exec_unit = UNIT_BRANCH;
                imm_src   = 3'b010; // B-type immediate
                is_branch = 1'b1;
                alu_op    = ALU_SUB; // Comparison math
            end

            // 4. JAL (J-Type Jump & Link)
            7'b1101111: begin
                use_rs1   = 1'b0;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000); // Writes PC+4 return address to rd
                exec_unit = UNIT_BRANCH;
                imm_src   = 3'b011; // J-type immediate
                is_jump   = 1'b1;
                alu_op    = ALU_ADD;
            end

            // 5. JALR (I-Type Indirect Jump & Link)
            7'b1100111: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000);
                exec_unit = UNIT_BRANCH;
                imm_src   = 3'b000; // I-type immediate
                is_jalr   = 1'b1;
                alu_op    = ALU_ADD;
            end

            // 6. I-Type Arithmetic e.g., ADDI, SLTI, ANDI, ORI, XORI, SLLI, SRLI
            7'b0010011: begin
                use_rs1   = 1'b1;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000);
                exec_unit = UNIT_ALU;
                imm_src   = 3'b000; // I-type immediate

                case (funct3)
                    3'b000: alu_op = ALU_ADD;  // ADDI
                    3'b010: alu_op = ALU_SLT;  // SLTI
                    3'b011: alu_op = ALU_SLTU; // SLTIU
                    3'b100: alu_op = ALU_XOR;  // XORI
                    3'b110: alu_op = ALU_OR;   // ORI
                    3'b111: alu_op = ALU_AND;  // ANDI
                    3'b001: alu_op = ALU_SLL;  // SLLI
                    3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRAI vs SRLI
                    default: alu_op = ALU_ADD;
                endcase
            end

            // 7. R-Type Arithmetic & Hardware Multiply (MUL/DIV)
            7'b0110011: begin
                use_rs1 = 1'b1;
                use_rs2 = 1'b1;
                use_rd  = (rd != 5'b00000);

                if (funct7 == 7'b0000001) begin
                    // Hardware M-extension (MUL, DIV, REM)
                    exec_unit = UNIT_MUL;
                    alu_op    = ALU_ADD;
                end else begin
                    // Standard R-type ALU math
                    exec_unit = UNIT_ALU;
                    case (funct3)
                        3'b000: alu_op = (funct7[5]) ? ALU_SUB : ALU_ADD; // SUB vs ADD
                        3'b001: alu_op = ALU_SLL;
                        3'b010: alu_op = ALU_SLT;
                        3'b011: alu_op = ALU_SLTU;
                        3'b100: alu_op = ALU_XOR;
                        3'b101: alu_op = (funct7[5]) ? ALU_SRA : ALU_SRL; // SRA vs SRL
                        3'b110: alu_op = ALU_OR;
                        3'b111: alu_op = ALU_AND;
                        default: alu_op = ALU_ADD;
                    endcase
                end
            end

            // 8. LUI (U-Type Load Upper Immediate)
            7'b0110111: begin
                use_rs1   = 1'b0;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000);
                exec_unit = UNIT_ALU;
                imm_src   = 3'b100; // U-type immediate
                alu_op    = ALU_ADD;
            end

            // 9. AUIPC (U-Type Add Upper Immediate to PC)
            7'b0010111: begin
                use_rs1   = 1'b0;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000);
                exec_unit = UNIT_ALU;
                imm_src   = 3'b100; // U-type immediate
                alu_op    = ALU_ADD;
                is_auipc  = 1'b1;
            end

            // 10. FENCE (Memory Barrier / NOP)
            7'b0001111: begin
                use_rs1   = 1'b0;
                use_rs2   = 1'b0;
                use_rd    = 1'b0;
                exec_unit = UNIT_ALU;
                imm_src   = 3'b000;
                alu_op    = ALU_ADD;
            end

            // 11. SYSTEM (ECALL, EBREAK, CSR)
            7'b1110011: begin
                use_rs1   = 1'b0;
                use_rs2   = 1'b0;
                use_rd    = (rd != 5'b00000);
                exec_unit = UNIT_ALU;
                imm_src   = 3'b000;
                alu_op    = ALU_ADD;
            end

            default: ;
        endcase
    end
endmodule
