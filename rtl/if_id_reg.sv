module if_id_reg (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        clear,            // Flush control
    input  logic        en,               // Stall control (1 = advance, 0 = freeze)
    input  logic        stall_slot1_only, // Advance Slot 1 to Slot 0, stall Fetch
    
    // Slot 0 (Primary Instruction)
    input  logic        if_valid0,
    input  logic [31:0] if_pc0,
    input  logic [31:0] if_instr0,
    input  logic        if_pred_taken0,
    input  logic [31:0] if_pred_target0,
    input  logic [7:0]  if_ghr0,

    output logic        id_valid0,
    output logic [31:0] id_pc0,
    output logic [31:0] id_instr0,
    output logic        id_pred_taken0,
    output logic [31:0] id_pred_target0,
    output logic [7:0]  id_ghr0,

    // Slot 1 (Secondary Superscalar Instruction)
    input  logic        if_valid1,
    input  logic [31:0] if_pc1,
    input  logic [31:0] if_instr1,
    input  logic        if_pred_taken1,
    input  logic [31:0] if_pred_target1,
    input  logic [7:0]  if_ghr1,

    output logic        id_valid1,
    output logic [31:0] id_pc1,
    output logic [31:0] id_instr1,
    output logic        id_pred_taken1,
    output logic [31:0] id_pred_target1,
    output logic [7:0]  id_ghr1,

    // Legacy backwards-compatible aliases
    output logic [31:0] id_pc,
    output logic [31:0] id_instr
);

    assign id_pc    = id_pc0;
    assign id_instr = id_instr0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_valid0       <= 1'b0;
            id_pc0          <= 32'b0;
            id_instr0       <= 32'h00000013;
            id_pred_taken0  <= 1'b0;
            id_pred_target0 <= 32'b0;
            id_ghr0         <= 8'b0;

            id_valid1       <= 1'b0;
            id_pc1          <= 32'b0;
            id_instr1       <= 32'h00000013;
            id_pred_taken1  <= 1'b0;
            id_pred_target1 <= 32'b0;
            id_ghr1         <= 8'b0;
        end 
        else if (clear) begin
            id_valid0       <= 1'b0;
            id_pc0          <= 32'b0;
            id_instr0       <= 32'h00000013;
            id_pred_taken0  <= 1'b0;
            id_pred_target0 <= 32'b0;
            id_ghr0         <= 8'b0;

            id_valid1       <= 1'b0;
            id_pc1          <= 32'b0;
            id_instr1       <= 32'h00000013;
            id_pred_taken1  <= 1'b0;
            id_pred_target1 <= 32'b0;
            id_ghr1         <= 8'b0;
        end 
        else if (stall_slot1_only) begin
            // Shift Slot 1 into Slot 0 and invalidate Slot 1
            id_valid0       <= id_valid1;
            id_pc0          <= id_pc1;
            id_instr0       <= id_instr1;
            id_pred_taken0  <= id_pred_taken1;
            id_pred_target0 <= id_pred_target1;
            id_ghr0         <= id_ghr1;

            id_valid1       <= 1'b0;
            id_pc1          <= 32'b0;
            id_instr1       <= 32'h00000013;
            id_pred_taken1  <= 1'b0;
            id_pred_target1 <= 32'b0;
            id_ghr1         <= 8'b0;
        end
        else if (en) begin
            id_valid0       <= if_valid0;
            id_pc0          <= if_pc0;
            id_instr0       <= if_instr0;
            id_pred_taken0  <= if_pred_taken0;
            id_pred_target0 <= if_pred_target0;
            id_ghr0         <= if_ghr0;

            id_valid1       <= if_valid1;
            id_pc1          <= if_pc1;
            id_instr1       <= if_instr1;
            id_pred_taken1  <= if_pred_taken1;
            id_pred_target1 <= if_pred_target1;
            id_ghr1         <= if_ghr1;
        end
    end

endmodule
