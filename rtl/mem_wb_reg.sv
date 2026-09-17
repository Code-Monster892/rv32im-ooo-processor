import pipeline_types::*;

module mem_wb_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear,
    input  logic        en,

    input  mem_wb_reg_t in,
    output mem_wb_reg_t out
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || clear) begin
            out <= '0;
        end
        else if (en) begin
            out <= in;
        end
    end

endmodule
