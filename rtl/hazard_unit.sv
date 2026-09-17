module hazard_unit (
    // ID Stage Inputs (for Load-Use Stall detection)
    input  logic [4:0] rs1_d,
    input  logic [4:0] rs2_d,
    
    // EX Stage Inputs (for Forwarding & Load-Use Stall detection)
    input  logic [4:0] rs1_e,
    input  logic [4:0] rs2_e,
    input  logic [4:0] rd_e,
    input  logic [2:0] result_src_e, // 3'b001 = Load
    input  logic       pc_src_e,      // High when Branch is taken or Jump occurs in EX stage
    
    // MEM Stage Inputs
    input  logic       reg_write_m,
    input  logic [4:0] rd_m,
    
    // WB Stage Inputs
    input  logic       reg_write_w,
    input  logic [4:0] rd_w,
    
    // Forwarding Outputs for EX Stage (ALU)
    output logic [1:0] forward_a_e,
    output logic [1:0] forward_b_e,
    
    // Stall & Flush Outputs
    output logic       stall_f,
    output logic       stall_d,
    output logic       flush_d,        // Flushes IF/ID on Branch Taken in EX
    output logic       flush_e         // Flushes ID/EX on Load-Use Stall or Branch Taken in EX
);

    // 1. EX-STAGE FORWARDING LOGIC (ALU Math & Branch Comparisons)
    always_comb begin
        if ((reg_write_m == 1'b1) && (rd_m != 5'b0) && (rd_m == rs1_e)) begin
            forward_a_e = 2'b10; // EX/MEM Forward
        end
        else if ((reg_write_w == 1'b1) && (rd_w != 5'b0) && (rd_w == rs1_e)) begin
            forward_a_e = 2'b01; // MEM/WB Forward
        end
        else begin
            forward_a_e = 2'b00; // No Forward
        end
    end

    always_comb begin
        if ((reg_write_m == 1'b1) && (rd_m != 5'b0) && (rd_m == rs2_e)) begin
            forward_b_e = 2'b10; // EX/MEM Forward
        end
        else if ((reg_write_w == 1'b1) && (rd_w != 5'b0) && (rd_w == rs2_e)) begin
            forward_b_e = 2'b01; // MEM/WB Forward
        end
        else begin
            forward_b_e = 2'b00; // No Forward
        end
    end

    // 2. LOAD-USE HAZARD STALL LOGIC
    logic load_use_hazard;

    always_comb begin
        if ((result_src_e == 3'b001) && (rd_e != 5'b0) &&
            ((rd_e == rs1_d) || (rd_e == rs2_d))) begin
            load_use_hazard = 1'b1;
        end
        else begin
            load_use_hazard = 1'b0;
        end
    end

    // Stall IF and ID stages during a Load-Use hazard
    assign stall_f = load_use_hazard;
    assign stall_d = load_use_hazard;

    // 3. FLUSH LOGIC (Wrong-Path Execution Recovery)
    // When a branch is taken in EX (pc_src_e = 1), flush both IF/ID and ID/EX!
    // When a load-use hazard occurs, flush ID/EX to inject a NOP bubble!
    assign flush_d = pc_src_e;
    assign flush_e = pc_src_e;

endmodule
