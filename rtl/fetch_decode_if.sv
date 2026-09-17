// Fetch to Decode Stage Decoupled Interface
interface fetch_decode_if (
    input logic clk,
    input logic rst_n
);
    import pipeline_types::*;

    logic           valid;
    logic           ready;
    logic           flush;
    fetch_payload_t data;

    // Master port (Fetch Stage Producer)
    modport Master (
        output valid, data,
        input  ready, flush
    );

    // Slave port (Decode Stage Consumer)
    modport Slave (
        input  valid, data,
        output ready,
        input  flush
    );
endinterface
