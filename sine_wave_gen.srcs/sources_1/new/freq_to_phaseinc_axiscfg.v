`timescale 1ns / 1ps

module freq_to_phaseinc_axiscfg #(
    parameter integer PHASE_WIDTH = 48,           // match DDS "Phase Width"
    parameter integer DDS_CLK_HZ  = 125_000_000   // DDS aclk frequency (Hz)
)(
    input  wire                         aclk,
    input  wire                         aresetn,

    // Command inputs
    input  wire [31:0]                  freq_hz,      // 1e6..32e6, 1 kHz step
    input  wire                         load_strobe,  // 1-cycle pulse

    // AXIS-Config Master (to DDS s_axis_config)
    output reg  [PHASE_WIDTH-1:0]       m_axis_tdata,
    output reg                          m_axis_tvalid,
    input  wire                         m_axis_tready
);
    // -------- Phase increment: round( freq * 2^P / Fclk ) --------
    localparam integer NUM_W = 32 + PHASE_WIDTH + 1; // +1 for carry
    // Make explicit widths so the carry is preserved in the addition:
    wire [NUM_W-1:0] freq_shifted_w = {1'b0, freq_hz, {PHASE_WIDTH{1'b0}}};     // 1 + 32 + P
    wire [NUM_W-1:0] half_fclk_w    = {{(NUM_W-32){1'b0}}, (DDS_CLK_HZ >> 1)};  // zero-extend 32b
    wire [NUM_W-1:0] num_rounded    = freq_shifted_w + half_fclk_w;
    wire [PHASE_WIDTH-1:0] phase_inc = num_rounded / DDS_CLK_HZ;

    // -------- AXIS handshaking --------
    always @(posedge aclk) begin
        if (!aresetn) begin
            m_axis_tdata  <= {PHASE_WIDTH{1'b0}};
            m_axis_tvalid <= 1'b0;
        end else begin
            if (m_axis_tready)
                m_axis_tvalid <= 1'b1;

            if (load_strobe && m_axis_tvalid) begin
                m_axis_tdata  <= phase_inc;
                m_axis_tvalid <= 1'b1;
            end
        end
    end
endmodule
