module multiplier (
    input  logic [31:0] src1,
    input  logic [31:0] src2,
    input  logic [2:0]  funct3,
    output logic [31:0] mul_result
);
    logic [63:0] full_result;
    logic signed [63:0] signed_src1, signed_src2;
    logic [63:0] unsigned_src1, unsigned_src2;
    
    assign signed_src1   = {{32{src1[31]}}, src1}; 
    assign signed_src2   = {{32{src2[31]}}, src2}; 
    assign unsigned_src1 = {32'b0, src1};        
    assign unsigned_src2 = {32'b0, src2};        
    always_comb begin
        full_result = 64'b0; // Prevent latches!
        case(funct3)
            3'b000: mul_result = src1 * src2;
            3'b001: begin
                full_result = signed_src1 * signed_src2;
                mul_result  = full_result[63:32];
            end
            3'b010: begin
                full_result = signed_src1 * $signed(unsigned_src2);
                mul_result  = full_result[63:32];
            end
            3'b011: begin
                full_result = unsigned_src1 * unsigned_src2;
                mul_result  = full_result[63:32];
            end
            3'b100: begin
                if (src2 == 0) mul_result = 32'hFFFFFFFF;
                else if (src1 == 32'h80000000 && src2 == 32'hFFFFFFFF) mul_result = 32'h80000000;
                else mul_result = $signed(src1) / $signed(src2);
            end
            3'b101: begin
                if (src2 == 0) mul_result = 32'hFFFFFFFF;
                else mul_result = src1 / src2;
            end
            3'b110: begin
                if (src2 == 0) mul_result = src1;
                else if (src1 == 32'h80000000 && src2 == 32'hFFFFFFFF) mul_result = 32'b0;
                else mul_result = $signed(src1) % $signed(src2);
            end
            3'b111: begin
                if (src2 == 0) mul_result = src1;
                else mul_result = src1 % src2;
            end
            default: mul_result = 32'b0;
        endcase
    end
endmodule
