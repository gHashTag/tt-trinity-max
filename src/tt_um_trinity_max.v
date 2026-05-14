`default_nettype none
// tt_um_trinity_max.v - TinyTapeout TRI-1 Max SKU top.
// Apache-2.0
// SPDX-License-Identifier: Apache-2.0
//
// TRI-1 Max = dual-cluster (2 × mesh_2x2 = 8 tiles) Trinity GF16 ternary
// MAC silicon SKU for TTSKY26b (close: 2026-05-18). Stretch member of
// the TRI-1 Triad (Nano / Mid / Max). Maximises tile count under the
// hard 2-bit packet dst constraint by stacking two independent crossbars
// behind a supervisor (see trinity_dual_cluster.v for rationale).
//
// Architectural contract:
//   - Canonical default path: combinational gf16_dot4(1,2,3,4)=0x47C0 on
//     {uio_out, uo_out} after reset — IDENTICAL to Nano + Mid, the
//     TG-TRIAD-X anchor (Theorem 36.1, PhD Ch.36).
//   - load_mode=1: nibble-strobed packet ingress, dual-cluster fabric,
//     8 addressable tiles via lane[3] = cluster_sel.
//
// R-SI-1: zero new `*` in synthesisable RTL. Lines: ~190.

`include "trinity_packet.vh"

module tt_um_trinity_max (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_oe,
    output wire [7:0] uio_out,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // ------------------------------------------------------------------
    // Canonical default path: gf16_dot4(1.0,2.0,3.0,4.0) = 0x47C0
    // ------------------------------------------------------------------
    wire [15:0] canonical_dot;
    gf16_dot4 u_canon (
        .a0(16'h3E00), .a1(16'h4000), .a2(16'h4100), .a3(16'h4200),
        .b0(16'h3E00), .b1(16'h4000), .b2(16'h4100), .b3(16'h4200),
        .result(canonical_dot)
    );

    // ------------------------------------------------------------------
    // Strobe ingress (host drives uio_in as a byte stream, 4 beats per
    // 32-bit packet, controlled by ui_in[7:4]).
    //   ui_in[0]   = load_mode (0=canonical, 1=packet)
    //   ui_in[7]   = byte_valid strobe
    //   ui_in[6:5] = beat index (0..3, LSB byte first)
    //   ui_in[4]   = packet_commit (rising edge -> in_valid pulse)
    //   ui_in[3]   = host_out_ready (host says "I latched eject byte")
    //   ui_in[2:1] = eject beat index (0..3, host drives the read cursor)
    // ------------------------------------------------------------------
    wire        load_mode      = ui_in[0];
    wire        byte_valid     = ui_in[7];
    wire [1:0]  in_beat        = ui_in[6:5];
    wire        commit_s       = ui_in[4];
    wire        eject_ready    = ui_in[3];
    wire [1:0]  out_beat       = ui_in[2:1];

    reg [31:0] in_pkt_q;
    reg        in_valid_q;

    reg commit_s_q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) commit_s_q <= 1'b0;
        else        commit_s_q <= commit_s;
    end
    wire commit_rise = commit_s && !commit_s_q && load_mode;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_pkt_q   <= 32'h0;
            in_valid_q <= 1'b0;
        end else if (load_mode) begin
            if (byte_valid) begin
                case (in_beat)
                    2'd0: in_pkt_q[7:0]   <= uio_in;
                    2'd1: in_pkt_q[15:8]  <= uio_in;
                    2'd2: in_pkt_q[23:16] <= uio_in;
                    2'd3: in_pkt_q[31:24] <= uio_in;
                endcase
            end
            in_valid_q <= commit_rise;
        end else begin
            in_valid_q <= 1'b0;
        end
    end

    // ------------------------------------------------------------------
    // Dual-cluster fabric (8 tiles via lane[3] cluster select)
    // ------------------------------------------------------------------
    wire [31:0] host_out_pkt;
    wire        host_out_valid;
    wire        host_in_ready;
    wire [15:0] dbg_tile0;
    wire [15:0] dbg_tile4;

    trinity_dual_cluster u_fabric (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (in_pkt_q),
        .host_in_valid   (in_valid_q),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (eject_ready),
        .dbg_tile0_result(dbg_tile0),
        .dbg_tile4_result(dbg_tile4)
    );

    // ------------------------------------------------------------------
    // Output pin mux
    //   load_mode=0  -> {uio_out, uo_out} = canonical 0x47C0
    //   load_mode=1  -> {uio_out, uo_out} = byte from host_out_pkt selected
    //                                       by out_beat (host drives read cursor)
    // ------------------------------------------------------------------
    reg [15:0] eject_word;
    always @(*) begin
        case (out_beat)
            2'd0: eject_word = {host_out_pkt[7:0],   host_out_pkt[7:0]};
            2'd1: eject_word = {host_out_pkt[15:8],  host_out_pkt[15:8]};
            2'd2: eject_word = {host_out_pkt[23:16], host_out_pkt[23:16]};
            2'd3: eject_word = {host_out_pkt[31:24], host_out_pkt[31:24]};
        endcase
    end

    assign uo_out  = load_mode ? eject_word[7:0]  : canonical_dot[7:0];
    assign uio_out = load_mode ? eject_word[15:8] : canonical_dot[15:8];
    assign uio_oe  = 8'hFF;

    // Lint tie-offs (cover all currently-unused signals)
    wire _unused_ena = ena;
    wire _unused_host_in_ready = host_in_ready;
    wire _unused_dbg = |dbg_tile0 | |dbg_tile4;
    wire _unused_host_out_valid = host_out_valid;

endmodule

`default_nettype wire
