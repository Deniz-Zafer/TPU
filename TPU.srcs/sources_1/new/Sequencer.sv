`timescale 1ns / 1ps

// Sequencer: dizinin ve belleklerin "sefi".
//   IDLE -> LOAD (N cycle) -> STREAM (M cycle) -> DRAIN (son satir yazilana kadar) -> DONE -> IDLE
//
// Uc parcadan olusur:
//   1) durum + sayaclar        (always_ff)  : ne zaman hangi duruma gececegiz
//   2) adres/yazma cikislari   (always_comb): durum + sayactan hesaplanir
//   3) mode / act_valid        (always_ff)  : adreslerden 1 cycle GECIKMELI (bellek 1 cycle gec cevap verir)

module Sequencer
    import general_pkg::*;
#(
    parameter int W_DEPTH = 64,
    parameter int A_DEPTH = 256,
    parameter int R_DEPTH = 256
)(
    input  logic                         clk,
    input  logic                         rst_n,

    // host
    input  logic                         start,
    input  logic                         accumulate,
    input  logic                         last_tile,
    input  logic [$clog2(A_DEPTH):0]     input_vector_count,
    input  logic [$clog2(W_DEPTH)-1:0]   weight_base,
    input  logic [$clog2(A_DEPTH)-1:0]   act_base,
    input  logic [$clog2(R_DEPTH)-1:0]   result_base,
    output logic                         busy,
    output logic                         done,

    // Systolic_Arr
    output mode_t                        mode,
    output logic                         act_valid,
    input  logic                         result_valid,

    // Memory
    output logic [$clog2(W_DEPTH)-1:0]   weight_raddr,
    output logic [$clog2(A_DEPTH)-1:0]   act_raddr,
    output logic                         result_we,
    output logic [$clog2(R_DEPTH)-1:0]   result_waddr,
    output logic                         act_swap,
    output logic                         result_swap,
    output logic                         result_accumulate
);

    localparam int W_AW = $clog2(W_DEPTH);
    localparam int A_AW = $clog2(A_DEPTH);
    localparam int R_AW = $clog2(R_DEPTH);

    typedef enum logic [3:0] {
        STATE_IDLE   = 4'b0000,
        STATE_LOAD   = 4'b0001,
        STATE_STREAM = 4'b0010,
        STATE_DRAIN  = 4'b0011,
        STATE_DONE   = 4'b0100
    } state_t;

    state_t          state;
    logic [A_AW:0]   cnt;          // LOAD ve STREAM'de "kacinci cycle"
    logic [A_AW:0]   result_cnt;   // kac sonuc satiri yazildi
    logic [A_AW:0]   m_q;          // start aninda yakalanan vektor sayisi
    logic [W_AW-1:0] weight_base_q;
    logic [A_AW-1:0] act_base_q;
    logic [R_AW-1:0] result_base_q;
    logic accumulate_q, last_tile_q;

    // ------------------------------------------------------------
    // 1) Durum makinesi + sayaclar
    //    Burada dongu YOK: her clock'ta bu blok bir kez calisir,
    //    "kac cycle bekle" demek = sayaci her clock'ta bir artirmak.
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= STATE_IDLE;
            cnt           <= '0;
            m_q           <= '0;
            weight_base_q <= '0;
            act_base_q    <= '0;
            result_base_q <= '0;
            last_tile_q   <= '0;
            accumulate_q  <= '0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    cnt <= '0;
                    if (start && input_vector_count != '0) begin
                        last_tile_q   <= last_tile;
                        accumulate_q  <= accumulate; 
                        m_q           <= input_vector_count;
                        weight_base_q <= weight_base;
                        act_base_q    <= act_base;
                        result_base_q <= result_base;
                        state         <= STATE_LOAD;
                    end
                end

                STATE_LOAD: begin
                    if (cnt == N-1) begin
                        cnt   <= '0;
                        state <= STATE_STREAM;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                STATE_STREAM: begin
                    if (cnt == m_q - 1'b1) begin
                        cnt   <= '0;
                        state <= STATE_DRAIN;
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                // DRAIN: son sonuc satiri yazilana kadar bekle
                STATE_DRAIN: begin
                    if (result_valid && result_cnt == m_q - 1'b1)
                        state <= STATE_DONE;
                end

                STATE_DONE: begin
                    state <= STATE_IDLE;
                end

                default: state <= STATE_IDLE;
            endcase
        end
    end

    // Yazilan sonuc satiri sayaci: dizi her gecerli satir verdiginde 1 artar.
    // (Ilk satir cycle 2N-1'de gelir, M buyukse STREAM bitmeden yazma baslar.)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                   result_cnt <= '0;
        else if (state == STATE_IDLE) result_cnt <= '0;
        else if (result_valid)        result_cnt <= result_cnt + 1'b1;
    end

    // ------------------------------------------------------------
    // 2) Adresler ve yazma sinyalleri (durum + sayactan hesaplanir)
    // ------------------------------------------------------------
    always_comb begin
        weight_raddr = '0;
        act_raddr    = '0;
        if (state == STATE_LOAD)
            weight_raddr = weight_base_q + W_AW'(N - 1 - cnt);   // N-1, N-2, ..., 0
        if (state == STATE_STREAM)
            act_raddr    = act_base_q + A_AW'(cnt);              // 0, 1, ..., M-1
    end

    assign result_we    = result_valid;
    assign result_waddr = result_base_q + R_AW'(result_cnt);

    // Girdi bankasi, ilk LOAD cycle'inda yer degistirir: host'un yeni doldurdugu banka
    // "compute bankasi" olur (LOAD 8 cycle surdugu icin STREAM'den cok once oturur).
    // Sonuc bankasi islem bitince (DONE) yer degistirir: host biten sonucu okuyabilsin.
    assign act_swap    = (state == STATE_LOAD) && (cnt == '0);
    assign result_swap = (state == STATE_DONE) && last_tile_q;

    assign result_accumulate = accumulate_q;
    assign busy = (state != STATE_IDLE);

    // ------------------------------------------------------------
    // 3) Dizinin gordugu sinyaller: adreslerden 1 cycle gecikmeli
    //    Adres cycle k'da verilir, bellek verisi cycle k+1'de gelir.
    //    mode/act_valid de k+1'de gecerli olmali ki veriyle ayni cycle'a denk gelsin.
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode      <= MODE_HOLD;
            act_valid <= 1'b0;
            done      <= 1'b0;
        end else begin
            case (state)
                STATE_LOAD:             mode <= MODE_LOAD;
                STATE_STREAM,
                STATE_DRAIN:            mode <= MODE_COMPUTE;
                default:                mode <= MODE_HOLD;
            endcase
            act_valid <= (state == STATE_STREAM);
            done      <= (state == STATE_DONE);   // swap'tan 1 cycle sonra: host okumaya hazir
        end
    end

endmodule
