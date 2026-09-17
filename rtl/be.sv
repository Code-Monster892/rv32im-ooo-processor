module be (
    input  logic [2:0]  funct3,
    input  logic [1:0]  offset,       // This is alu_result[1:0]
    input  logic [31:0] write_data,   // Raw 32-bit data from the Register File
    output logic [3:0]  mask,         // 4-bit wire to turn specific RAM bytes ON/OFF
    output logic [31:0] shifted_data  // The perfectly aligned data
);
    always @(*) begin
        // Default safe values
        mask = 4'b0000;
        shifted_data = write_data;
        case (funct3)
            3'b000: begin // sb (Store Byte - 8 bits)
                case (offset)
                    2'b00: begin mask = 4'b0001; shifted_data = {24'b0, write_data[7:0]}; end
                    2'b01: begin mask = 4'b0010; shifted_data = {16'b0, write_data[7:0],  8'b0}; end
                    2'b10: begin mask = 4'b0100; shifted_data = { 8'b0, write_data[7:0], 16'b0}; end
                    2'b11: begin mask = 4'b1000; shifted_data = {write_data[7:0], 24'b0}; end
                endcase
            end
            
            3'b001: begin // sh (Store Halfword - 16 bits)
                case (offset[1]) // We only care about the top bit (is it byte 0 or byte 2?)
                    1'b0: begin mask = 4'b0011; shifted_data = {16'b0, write_data[15:0]}; end
                    1'b1: begin mask = 4'b1100; shifted_data = {write_data[15:0], 16'b0}; end
                endcase
            end
            3'b010: begin // sw (Store Word - 32 bits)
                mask = 4'b1111; 
                shifted_data = write_data;
            end
            
            default: begin
                mask = 4'b0000; // If it's not a store instruction, mask all writes
                shifted_data = write_data;
            end
        endcase
    end
endmodule