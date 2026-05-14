`default_nettype none
// trinity_dual_cluster.v - 8-tile fabric = 2 x trinity_mesh_2x2 + cluster supervisor.
// Apache-2.0
// SPDX-License-Identifier: Apache-2.0
//
// Topology rationale (R-SI-1 / R-SI-7):
//   The 32-bit Trinity packet (trinity_packet.vh) reserves only 2 bits for
//   the tile dst field, so 4 is the hard cap of any single mesh in v0.
//   For Max we instantiate TWO mesh_2x2 clusters back-to-back and select
//   the cluster via lane[3] of the packet (a previously-reserved bit).
//   Cluster 0 hosts tiles 0..3, cluster 1 hosts tiles 4..7. Inside a
//   cluster the existing 2-bit dst routes to the right tile. No new `*`
//   operators are introduced — everything reuses combinational logic
//   already proven in Mid.
//
// Pin contract (host side identical to mesh_2x2):
//   - host_in_pkt[`TRN_PKT_LANE` bit 3] = cluster_sel (1 = cluster1)
//   - all other packet fields unchanged; the dual-cluster supervisor strips
//     lane[3] before forwarding to the chosen cluster
//   - host_out_pkt comes back with cluster id encoded back into lane[3]
//
// This keeps the Trinity packet ABI byte-identical to Mid for all 4-tile
// workloads — a packet with lane[3]=0 lands in cluster 0 and behaves
// exactly like Mid. Backward-compat preserved by construction.

`include "trinity_packet.vh"

module trinity_dual_cluster (
    input  wire                       clk,
    input  wire                       rst_n,

    // Host injection
    input  wire [`TRN_PKT_W-1:0]      host_in_pkt,
    input  wire                       host_in_valid,
    output wire                       host_in_ready,

    // Host ejection
    output reg  [`TRN_PKT_W-1:0]      host_out_pkt,
    output reg                        host_out_valid,
    input  wire                       host_out_ready,

    // Debug
    output wire [15:0]                dbg_tile0_result,
    output wire [15:0]                dbg_tile4_result
);

    wire cluster_sel = host_in_pkt[20];   // lane[3] re-purposed (was reserved)

    // --- Cluster 0 ---
    wire [`TRN_PKT_W-1:0] c0_in_pkt;
    wire                  c0_in_valid;
    wire                  c0_in_ready;
    wire [`TRN_PKT_W-1:0] c0_out_pkt;
    wire                  c0_out_valid;
    wire                  c0_out_ready;
    wire [15:0]           c0_dbg;

    // Strip cluster_sel from packet (clear lane[3])
    wire [`TRN_PKT_W-1:0] in_pkt_stripped = host_in_pkt & ~(32'h1 << 20);

    assign c0_in_pkt   = in_pkt_stripped;
    assign c0_in_valid = host_in_valid && (cluster_sel == 1'b0);

    trinity_mesh_2x2 u_cluster0 (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (c0_in_pkt),
        .host_in_valid   (c0_in_valid),
        .host_in_ready   (c0_in_ready),
        .host_out_pkt    (c0_out_pkt),
        .host_out_valid  (c0_out_valid),
        .host_out_ready  (c0_out_ready),
        .dbg_tile0_result(c0_dbg)
    );

    // --- Cluster 1 ---
    wire [`TRN_PKT_W-1:0] c1_in_pkt;
    wire                  c1_in_valid;
    wire                  c1_in_ready;
    wire [`TRN_PKT_W-1:0] c1_out_pkt;
    wire                  c1_out_valid;
    wire                  c1_out_ready;
    wire [15:0]           c1_dbg;

    assign c1_in_pkt   = in_pkt_stripped;
    assign c1_in_valid = host_in_valid && (cluster_sel == 1'b1);

    trinity_mesh_2x2 u_cluster1 (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (c1_in_pkt),
        .host_in_valid   (c1_in_valid),
        .host_in_ready   (c1_in_ready),
        .host_out_pkt    (c1_out_pkt),
        .host_out_valid  (c1_out_valid),
        .host_out_ready  (c1_out_ready),
        .dbg_tile0_result(c1_dbg)
    );

    // host_in_ready = chosen cluster's ready
    assign host_in_ready = cluster_sel ? c1_in_ready : c0_in_ready;

    // --- Eject arbiter: round-robin between cluster 0 / 1, re-stamp lane[3] ---
    reg rr;
    wire buffer_can_accept = !host_out_valid || host_out_ready;

    // Try the round-robin loser first to give fair priority alternation
    wire pick0 = c0_out_valid && (!c1_out_valid || rr == 1'b0);
    wire pick1 = c1_out_valid && (!c0_out_valid || rr == 1'b1);

    assign c0_out_ready = pick0 && buffer_can_accept;
    assign c1_out_ready = pick1 && buffer_can_accept;

    // Re-stamp cluster id back into lane[3] of the outbound packet
    wire [`TRN_PKT_W-1:0] c0_out_stamped = c0_out_pkt;          // cluster 0 -> lane[3]=0
    wire [`TRN_PKT_W-1:0] c1_out_stamped = c1_out_pkt | (32'h1 << 20);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rr             <= 1'b0;
            host_out_pkt   <= {`TRN_PKT_W{1'b0}};
            host_out_valid <= 1'b0;
        end else begin
            if (host_out_valid && host_out_ready)
                host_out_valid <= 1'b0;

            if (buffer_can_accept) begin
                if (pick0) begin
                    host_out_pkt   <= c0_out_stamped;
                    host_out_valid <= 1'b1;
                    rr             <= 1'b1;
                end else if (pick1) begin
                    host_out_pkt   <= c1_out_stamped;
                    host_out_valid <= 1'b1;
                    rr             <= 1'b0;
                end
            end
        end
    end

    assign dbg_tile0_result = c0_dbg;
    assign dbg_tile4_result = c1_dbg;

endmodule

`default_nettype wire
