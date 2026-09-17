// Rename to Dispatch (RS & ROB) Decoupled Interface
interface rename_dispatch_if (
    input logic clk,
    input logic rst_n
);
    import pipeline_types::*;

    logic            valid;
    logic            ready;
    logic            flush;
    rename_payload_t data;

    // Master port (Rename Stage Producer)
    modport Master (
        output valid, data,
        input  ready, flush
    );

    // Slave port (Dispatch Stage / RS / ROB Consumer)
    modport Slave (
        input  valid, data,
        output ready,
        input  flush
    );
endinterface
