module memory #(
    parameter WORDS = 4194304 // 16 Megabytes of RAM!
) (
    input  logic        clk,
    input  logic        rst_n,
    
    // Data Port
    input  logic        we,
    input  logic [3:0]  mask,      // 4 bit byte enable mask
    input  logic [31:0] address,   // Write address
    input  logic [31:0] write_data,
    input  logic [31:0] read_address, // Independent Load read address
    output logic [31:0] read_data,
    
    // Instruction Port (Dual 32-bit Words / 64-bit Read)
    input  logic [31:0] pc_address,
    output logic [31:0] instruction,
    output logic [31:0] instruction1
);

    // Memory array
    reg [31:0] mem [0:WORDS-1] /* verilator public */;

    // --- Pre-load Firmware ---
    initial begin
       $readmemh("firmware.hex", mem);
    end
    // --- Write logic (Synchronous) ---
    always @(posedge clk) begin
        if (we && rst_n) begin
            if (address[31:2] < WORDS) begin
                // Only overwrite specific data bytes where the mask bit is a '1'
                if (mask[0]) mem[address[31:2]][7:0]   <= write_data[7:0];
                if (mask[1]) mem[address[31:2]][15:8]  <= write_data[15:8];
                if (mask[2]) mem[address[31:2]][23:16] <= write_data[23:16];
                if (mask[3]) mem[address[31:2]][31:24] <= write_data[31:24];
            end
        end
    end

    // Read logic (Asynchronous/Combinational)
    always @(*) begin
        if (read_address[31:2] < WORDS) begin
            read_data = mem[read_address[31:2]]; 
        end else begin
            read_data = 32'b0;
        end

        if (pc_address[31:2] < WORDS) begin
            instruction = mem[pc_address[31:2]];
        end else begin
            instruction = 32'h00000013; // Safe NOP (addi x0, x0, 0)
        end

        if ((pc_address[31:2] + 1) < WORDS) begin
            instruction1 = mem[pc_address[31:2] + 1];
        end else begin
            instruction1 = 32'h00000013; // Safe NOP (addi x0, x0, 0)
        end
    end

endmodule
