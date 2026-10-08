`timescale 1ns / 1ps

module Systolic_Arr
    import general_pkg::*;
(
    input  logic  clk,
    input  logic  rst_n,
    input  mode_t mode,

    input  logic  act_valid,                    // 1: act_feed_arr'da gercek bir vektor var

    input  act_t  act_feed_arr    [N],
    input  act_t  weight_feed_arr [N],

    output acc_t  result_out_arr  [N],          // hizali sonuc satiri
    output logic  result_valid                  // 1: result_out_arr gecerli bir satir VE dizi bu cycle'da ilerliyor (COMPUTE)
);

    act_t act_feed    [N];
    acc_t psum_feed   [N];
    act_t weight_feed [N];
    acc_t raw_result  [N];                      // skew'li ham cikis
    act_t act_in_g    [N];                      // act_valid ile kapilanmis giris

    for (genvar i = 0; i < N; i++) begin : G_FEED
        assign psum_feed[i]   = '0;
        assign weight_feed[i] = weight_feed_arr[i];
        assign act_in_g[i]    = act_valid ? act_feed_arr[i] : '0;
    end

    // Tum gecikme hatlari (skew, de-skew, valid) mode'a gore:
    //   LOAD    -> sifirla
    //   COMPUTE -> ilerlet
    //   HOLD    -> dondur (dizinin geri kalaniyla birlikte)

    // Giris skew'i: satir r, aktivasyonu r cycle gecikmeli alir.
    for (genvar r = 0; r < N; r++) begin : SKEW
        if (r == 0) begin : NO_DELAY
            assign act_feed[r] = act_in_g[r];
        end else begin : DELAY
            act_t sr [r];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int k = 0; k < r; k++) sr[k] <= '0;
                end else begin
                    case (mode)
                        MODE_LOAD: begin
                            for (int k = 0; k < r; k++) sr[k] <= '0;
                        end
                        MODE_COMPUTE: begin
                            sr[0] <= act_in_g[r];
                            for (int k = 1; k < r; k++) sr[k] <= sr[k-1];
                        end
                        default: ;
                    endcase
                end
            end

            assign act_feed[r] = sr[r-1];
        end
    end

    PE_Cluster pe_cluster_inst (
        .clk        (clk),
        .rst_n      (rst_n),
        .mode       (mode),
        .act_feed   (act_feed),
        .psum_feed  (psum_feed),
        .weight_feed(weight_feed),
        .result_out (raw_result)
    );

    // Cikis de-skew'i: sutun c, sonucu N-1-c cycle geciktirir.
    for (genvar c = 0; c < N; c++) begin : DESKEW
        if (c == N-1) begin : NO_DELAY
            assign result_out_arr[c] = raw_result[c];
        end else begin : DELAY
            acc_t dl [N-1-c];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    for (int k = 0; k < N-1-c; k++) dl[k] <= '0;
                end else begin
                    case (mode)
                        MODE_LOAD: begin
                            for (int k = 0; k < N-1-c; k++) dl[k] <= '0;
                        end
                        MODE_COMPUTE: begin
                            dl[0] <= raw_result[c];
                            for (int k = 1; k < N-1-c; k++) dl[k] <= dl[k-1];
                        end
                        default: ;
                    endcase
                end
            end

            assign result_out_arr[c] = dl[N-2-c];
        end
    end

    // Valid hatti: giriste verilen act_valid, 2N-1 ilerleme kenari sonra result_valid olur.
    localparam int VALID_DEPTH = 2*N - 1;
    logic [VALID_DEPTH-1:0] valid_sr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_sr <= '0;
        end else begin
            case (mode)
                MODE_LOAD:    valid_sr <= '0;
                MODE_COMPUTE: valid_sr <= {valid_sr[VALID_DEPTH-2:0], act_valid};
                default: ;
            endcase
        end
    end

    // HOLD'da dizi ilerlemedigi icin ayni satir birden cok cycle gorunur;
    // sadece dizi ilerlerken (COMPUTE) gecerli sayiyoruz ki ayni sonuc bir kez yazilsin.
    assign result_valid = valid_sr[VALID_DEPTH-1] && (mode == MODE_COMPUTE);

endmodule
