module alu (
    input logic [3:0] alu_control, // <-- Upgraded to 4 bits
    input logic [31:0] src1,
    input logic [31:0] src2,
    output logic [31:0] alu_result,
    output logic zero 
);

always_comb begin
    case (alu_control)
        4'b0000: alu_result = src1 + src2;                             // ADD
        4'b1000: alu_result = src1 - src2;                             // SUB
        4'b0001: alu_result = src1 << src2[4:0];                       // SLL  (Shift Left Logical)
        4'b0010: alu_result = ($signed(src1) < $signed(src2)) ? 1 : 0; // SLT  (Set Less Than Signed)
        4'b0011: alu_result = (src1 < src2) ? 1 : 0;                   // SLTU (Set Less Than Unsigned)
        4'b0100: alu_result = src1 ^ src2;                             // XOR
        4'b0101: alu_result = src1 >> src2[4:0];                       // SRL  (Shift Right Logical)
        4'b1101: alu_result = $signed(src1) >>> src2[4:0];             // SRA  (Shift Right Arithmetic)
        4'b0110: alu_result = src1 | src2;                             // OR
        4'b0111: alu_result = src1 & src2;                             // AND
        default: alu_result = 32'b0;
    endcase
end

assign zero = (alu_result == 32'b0);

endmodule