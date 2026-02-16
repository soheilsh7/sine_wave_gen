`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 10/13/2025 10:37:26 AM
// Design Name: 
// Module Name: dds_amp_trunc_to_an9767
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////

// Truncation (shift-left by n from one-hot amp)
// to => 14-bit for AN9767 (AD9767). parallel Port-1 (P1_*).

module dds_amp_trunc_to_an9767 #(
    parameter integer DDS_OUT_WIDTH = 16  // DDS output width
)(
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 125000000" *)
    input  wire                         aclk,        // clock (DDS & DAC)
    input  wire                         aresetn,

    // From DDS Compiler (M_AXIS_DATA)
    input  wire [DDS_OUT_WIDTH-1:0]     dds_tdata,
    input  wire                         dds_tvalid,  // data update

    // n shift
    input  wire [3:0]                  n_shift,

    // To AN9767 (Port 1, parallel)
    (* X_INTERFACE_PARAMETER = "FREQ_HZ 125000000" *)
    output wire                         P1_CLK,      // sample clock
    output wire                         P1_WRT,      // write strobe = same as clock
    output reg  [13:0]                  P1_DATA      // offset-binary 14-bit
);

    // DAC strobes = sample clock
    assign P1_CLK = aclk;
    assign P1_WRT = aclk;


    // 1) shift amount (shamt) from one-hot amp (With priority)



    // 2) Sign-extend, shift-left by shamt, truncate to top 14 bits

    localparam integer EXT_W = DDS_OUT_WIDTH + 14; // headroom for taking MSBs
    wire signed [EXT_W-1:0] dds_sext = {{14{dds_tdata[DDS_OUT_WIDTH-1]}}, dds_tdata};
    wire signed [EXT_W-1:0] scaled   = dds_sext <<< n_shift;

    // Take 14 MSBs (truncation)
    wire signed [13:0] s14_tc = scaled[EXT_W-1 : 14];

    // ----------------------------------------------------------------
    // 3) Convert two's-complement -> 14-bit Offset-Binary for AN9767
    //     offset = +2^(14-1) = 0x2000
    // ----------------------------------------------------------------
    wire signed [13:0] s14_offbin = s14_tc + 14'h2000;

    // ----------------------------------------------------------------
    // 4) Register output data each sample clock (if dds_tvalid)
    // ----------------------------------------------------------------
    always @(posedge aclk) begin
        if (!aresetn) begin
            P1_DATA <= 14'h2000;     // mid-scale on reset
        end else begin
            if (dds_tvalid) begin
                P1_DATA <= s14_offbin;
            end
        end
    end

endmodule
