module signext (
    input  logic [31:0] instr,
    input  logic [2:0]  imm_src,  // updated to 3 bits
    
    output logic [31:0] imm_ext
);

    always @(*) begin 
        case (imm_src)
            3'b000 : imm_ext = {{20{instr[31]}}, instr[31:20]}; // I-Type
            3'b001 : imm_ext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; // S-Type
            3'b010 : imm_ext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; // B-Type
            3'b011 : imm_ext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; // J-Type
            3'b100: imm_ext = {instr[31:12], 12'b0}; // U-Type 
            
            default: imm_ext = 32'b0; 
        endcase
    end

endmodule