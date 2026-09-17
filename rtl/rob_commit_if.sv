// Reorder Buffer (ROB) to Retirement/Commit Interface
interface rob_commit_if (
    input logic clk,
    input logic rst_n
);
    import pipeline_types::*;

    rob_commit_payload_t payload;
    logic                flush_out;       // Asserted by ROB head on branch misprediction / exception
    word_t               flush_pc;        // Redirection target PC on misprediction

    // Master port (ROB Producer)
    modport Master (
        output payload, flush_out, flush_pc
    );

    // Slave port (Retirement & RAT Rollback Consumer)
    modport Slave (
        input payload, flush_out, flush_pc
    );
endinterface
