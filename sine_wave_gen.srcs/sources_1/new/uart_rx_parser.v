`timescale 1ns/1ps
// ';' as terminator:
// Step A) <digits> ;  --> freq_hz (+1 kHz quantize), cmd_ready pulse
// Step B) <digits> ;  --> n_shift (0..13), cmd_ready pulse

module uart_rx_parser #(
    parameter integer CLK_FREQ  = 125_000_000,   // 125 MHz
    parameter integer BAUD_RATE = 115_200        // baud
)(
    input  wire        clk,
    input  wire        resetn,
    input  wire        RX,

    // Raw byte output
    output reg  [7:0]  data_out,
    output reg         data_valid,

    // Parsed command outputs
    output reg [31:0]  freq_hz,   // 1..32 MHz, snapped to 1 kHz
    output reg  [3:0]  n_shift,   // 0..13
    output reg         cmd_ready, // pulse on each accepted field
    output reg         cmd_error  // pulse on bad field
);

    // =========================
    // UART RX (8N1)
    // =========================
    localparam integer CLKS_PER_BIT  = CLK_FREQ / BAUD_RATE;
    localparam integer HALF_BIT_CLKS = CLKS_PER_BIT/2;

    reg [15:0] clk_cnt = 0;
    reg [3:0]  bit_idx = 0;
    reg [9:0]  shifter = 10'h3FF; // {stop=1, data[7:0], start=1}
    reg        busy    = 1'b0;

    // input sync
    reg rx_ff1, rx_ff2;
    always @(posedge clk) begin
        rx_ff1 <= RX;
        rx_ff2 <= rx_ff1;
    end
    wire rx_sync = rx_ff2;

    // byte receiver -> data_out/data_valid
    always @(posedge clk) begin
        if (!resetn) begin
            clk_cnt    <= 0;
            bit_idx    <= 0;
            shifter    <= 10'h3FF;
            busy       <= 1'b0;
            data_out   <= 8'h00;
            data_valid <= 1'b0;
        end else begin
            data_valid <= 1'b0; // default

            if (!busy) begin
                if (rx_sync == 1'b0) begin // start bit detect
                    busy     <= 1'b1;
                    clk_cnt  <= 0;
                    bit_idx  <= 0;
                end
            end else begin
                clk_cnt <= clk_cnt + 1;

                if (bit_idx == 0) begin // align middle of start bit
                    if (clk_cnt == HALF_BIT_CLKS) begin
                        clk_cnt <= 0;
                        bit_idx <= 1;
                    end
                end else if (bit_idx >= 1 && bit_idx <= 8) begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt            <= 0;
                        shifter[bit_idx]   <= rx_sync; // LSB-first
                        bit_idx            <= bit_idx + 1;
                    end
                end else if (bit_idx == 9) begin // stop bit time
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt    <= 0;
                        busy       <= 1'b0;
                        bit_idx    <= 0;
                        data_out   <= {shifter[8],shifter[7],shifter[6],shifter[5],
                                       shifter[4],shifter[3],shifter[2],shifter[1]};
                        data_valid <= 1'b1; // one-cycle strobe
                        shifter    <= 10'h3FF;
                    end
                end
            end
        end
    end

    // =========================
    // TWO-STEP PARSER (digits -> ';')
    // =========================
    localparam ST_FREQ = 1'b0;
    localparam ST_AMP  = 1'b1;

    reg        state;       // 0: collecting freq, 1: collecting n
    reg [31:0] acc_val;     // accumulates digits for current field
    reg        have_digit;  // seen any digit in current field

    // byte classification (only when data_valid)
    wire byte_is_sp    = (data_out==" " || data_out=="\t" || data_out=="\r" || data_out=="\n");
    wire byte_is_term  = (data_out==";");     // field terminator
    wire byte_is_digit = (data_out>="0" && data_out<="9");

    always @(posedge clk) begin
        if (!resetn) begin
            state      <= ST_FREQ;
            acc_val    <= 32'd0;
            have_digit <= 1'b0;
            freq_hz    <= 32'd0;
            n_shift    <= 4'd0;
            cmd_ready  <= 1'b0;
            cmd_error  <= 1'b0;
        end else begin
            cmd_ready  <= 1'b0;
            cmd_error  <= 1'b0;

            if (data_valid) begin
                if (byte_is_sp) begin
                    // ignore whitespace anywhere
                end
                else if (byte_is_digit) begin
                    acc_val    <= (acc_val * 10) + (data_out - "0");
                    have_digit <= 1'b1;
                end
                else if (byte_is_term) begin
                    // finalize current field
                    if (!have_digit) begin
                        // empty field -> error, reset flow to FREQ
                        cmd_error  <= 1'b1;
                        acc_val    <= 32'd0;
                        have_digit <= 1'b0;
                        state      <= ST_FREQ;
                    end else if (state == ST_FREQ) begin
                        // validate & snap frequency
                        if (acc_val < 32'd1_000_000 || acc_val > 32'd32_000_000) begin
                            cmd_error <= 1'b1;
                            state     <= ST_FREQ; // ask freq again
                        end else begin
                            freq_hz   <= acc_val - (acc_val % 32'd1000); // 1 kHz step
                            cmd_ready <= 1'b1;  // "frequency accepted"
                            state     <= ST_AMP; // now wait for n
                        end
                        acc_val    <= 32'd0;
                        have_digit <= 1'b0;
                    end else begin // ST_AMP
                        if (acc_val[5:0] > 6'd13) begin
                            cmd_error <= 1'b1;
                            state     <= ST_FREQ; // after bad n, restart
                        end else begin
                            n_shift   <= acc_val[3:0];
                            cmd_ready <= 1'b1;    // "amplitude accepted"
                            state     <= ST_FREQ; // restart cycle
                        end
                        acc_val    <= 32'd0;
                        have_digit <= 1'b0;
                    end
                end
                else begin
                    // any other char -> error & restart
                    cmd_error  <= 1'b1;
                    acc_val    <= 32'd0;
                    have_digit <= 1'b0;
                    state      <= ST_FREQ;
                end
            end
        end
    end

endmodule
