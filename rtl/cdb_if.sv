// Common Data Bus (CDB) Result Broadcast Interface
interface cdb_if (
    input logic clk,
    input logic rst_n
);
    import pipeline_types::*;

    cdb_payload_t payload;

    // Master port (Execution Unit Producer)
    modport Master (
        output payload
    );

    // Monitor port (RS, PRF, ROB Consumers listening to CDB)
    modport Monitor (
        input payload
    );
endinterface
