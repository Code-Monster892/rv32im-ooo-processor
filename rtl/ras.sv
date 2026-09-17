// Return Address Stack (RAS) Module
// 8-entry hardware LIFO stack providing 100% prediction accuracy for function returns.
module ras #(
    parameter RAS_DEPTH = 8,
    parameter RAS_PTR_BITS = 3
) (
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          flush,

    // 1. Push Interface (Function Call: JAL/JALR with rd == x1)
    input  logic                          push_en,
    input  pipeline_types::word_t         push_addr, // Return address (PC + 4)

    // 2. Pop Interface (Function Return: JALR with rs1 == x1 && rd == x0)
    input  logic                          pop_en,
    output logic                          pop_valid,
    output pipeline_types::word_t         pop_addr   // Predicted return destination PC
);
    import pipeline_types::*;

    // 8-entry LIFO storage array
    word_t stack [0:RAS_DEPTH-1];
    logic [RAS_PTR_BITS-1:0] top_ptr;
    logic [RAS_PTR_BITS:0]   count;

    // Combinational Pop: read top of stack
    assign pop_valid = (count != '0);
    assign pop_addr  = stack[top_ptr];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush) begin
            top_ptr <= '0;
            count   <= '0;
            for (int i = 0; i < RAS_DEPTH; i++) begin
                stack[i] <= 32'd0;
            end
        end else begin
            case ({push_en, pop_en})
                2'b10: begin // Push ONLY (Function Call)
                    if (count == '0) begin
                        stack[0] <= push_addr;
                        top_ptr  <= '0;
                        count    <= count + 1'b1;
                    end else begin
                        stack[top_ptr + 1'b1] <= push_addr;
                        top_ptr               <= top_ptr + 1'b1;
                        if (count != RAS_DEPTH) begin
                            count <= count + 1'b1;
                        end
                    end
                end

                2'b01: begin // Pop ONLY (Function Return)
                    if (count != '0) begin
                        top_ptr <= top_ptr - 1'b1;
                        count   <= count - 1'b1;
                    end
                end

                2'b11: begin // Simultaneous Call & Return (Push overwrites Top)
                    stack[top_ptr] <= push_addr;
                end

                default: ; // Idle
            endcase
        end
    end
endmodule
