module reader (
    input  logic [2:0]  funct3,
    input  logic [1:0]  offset,
    input  logic [31:0] raw_read_data,
    output logic [31:0] final_read_data
);

    logic [7:0]  extracted_byte;
    logic [15:0] extracted_halfword;

    // 1. Extract the specific Byte
    always @(*) begin
        case (offset)
            2'b00: extracted_byte = raw_read_data[7:0];
            2'b01: extracted_byte = raw_read_data[15:8];
            2'b10: extracted_byte = raw_read_data[23:16];
            2'b11: extracted_byte = raw_read_data[31:24];
        endcase
    end

    // 2. Extract the specific Halfword
    always @(*) begin
        case (offset[1]) // Only look at the top offset bit
            1'b0: extracted_halfword = raw_read_data[15:0];
            1'b1: extracted_halfword = raw_read_data[31:16];
        endcase
    end

    // 3. Extend the extracted data back to 32 bits based on the instruction
    always @(*) begin
        case (funct3)
            3'b000: final_read_data = {{24{extracted_byte[7]}}, extracted_byte};       // lb  (Sign-Extend)
            3'b001: final_read_data = {{16{extracted_halfword[15]}}, extracted_halfword}; // lh  (Sign-Extend)
            3'b010: final_read_data = raw_read_data;                                   // lw  (Raw 32-bits)
            3'b100: final_read_data = {24'b0, extracted_byte};                         // lbu (Zero-Extend)
            3'b101: final_read_data = {16'b0, extracted_halfword};                     // lhu (Zero-Extend)
            default: final_read_data = raw_read_data;                                  // Default to safe 32-bits
        endcase
    end

endmodule