`timescale 1ns / 1ps

module PE_Cluster
    import general_pkg::*;
(
    input  logic clk,
    input  logic rst_n,
    input  mode_t mode,

    input  act_t act_feed    [N],
    input  acc_t psum_feed   [N],
    input  act_t weight_feed [N],

    output acc_t result_out  [N]
);

    // Kenar dahil bus dizileri: indeks 0 = dis besleme, son indeks = cikis
    act_t act_bus    [N][N+1];
    acc_t psum_bus   [N+1][N];
    act_t weight_bus [N+1][N];

    for (genvar r = 0; r < N; r++) begin : G_LEFT
        assign act_bus[r][0] = act_feed[r];
    end

    for (genvar c = 0; c < N; c++) begin : G_TOP_BOTTOM
        assign psum_bus[0][c]   = psum_feed[c];
        assign weight_bus[0][c] = weight_feed[c];
        assign result_out[c]    = psum_bus[N][c];
    end

    for (genvar r = 0; r < N; r++) begin : ROW
        for (genvar c = 0; c < N; c++) begin : COL
            PE pe_inst (
                .clk       (clk),
                .rst_n     (rst_n),
                .mode      (mode),
                .act_in    (act_bus[r][c]),
                .weight_in (weight_bus[r][c]),
                .psum_in   (psum_bus[r][c]),
                .act_out   (act_bus[r][c+1]),
                .weight_out(weight_bus[r+1][c]),
                .psum_out  (psum_bus[r+1][c])
            );
        end
    end

endmodule
