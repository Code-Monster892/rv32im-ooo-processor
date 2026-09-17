import pipeline_types::*;

module id_ex_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear,  // Flush control (high active)
    input  logic        en,     // Stall control (high active = enable)

    input  id_ex_reg_t  in,     // Input struct from ID stage
    output id_ex_reg_t  out     // Output struct to EX stage
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            // Reset or flush: zero out all signals in 1 single line
            out <= '0;
        end
        else if (en) begin
            // Enable: copy entire struct in 1 single line!
            out <= in;
        end
    end

endmodule
