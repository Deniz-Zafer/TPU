`timescale 1ns / 1ps

module TPU_Core
import general_pkg::*;(
    //common
    input logic     clk, rst_n,

    //start registers
    input logic       start,
    input logic [8:0] input_vector_count,
    input logic [5:0] weight_base,
    input logic [7:0] act_base,
    input logic [7:0] result_base,
    input logic accumulate,
    input logic last_tile,

    //state signals
    output logic busy,
    output logic done,

    //weight input
    input logic       w_we,
    input logic [5:0] w_addr,
    input act_t       w_wdata [N],

    //act input
    input logic       a_we,
    input logic [7:0] a_addr,
    input act_t       a_wdata [N],

    //result output
    input logic [7:0] r_addr,
    output acc_t      r_rdata [N],

    //post-processor (ReLU + requantization: Result_Buffer -> Act_Buffer)
    input logic       pp_start,
    input logic [8:0] pp_row_count,
    input logic [7:0] pp_src_base,      // Result_Buffer'da okunacak ilk satir
    input logic [7:0] pp_dst_base,      // Act_Buffer'da yazilacak ilk satir
    input logic [4:0] pp_shift,
    input logic       pp_relu_en,
    output logic      pp_busy,
    output logic      pp_done
    );

    // ------------------------------------------------------------
    // Ic kablolar (host'un gormedigi, modullerin kendi aralarindaki sinyaller)
    // ------------------------------------------------------------
    // Sequencer <-> Systolic_Arr
    mode_t       mode;
    logic        act_valid;
    logic        result_valid;

    // Sequencer -> Memory
    logic [5:0]  weight_raddr;
    logic [7:0]  act_raddr;
    logic        result_we;
    logic [7:0]  result_waddr;
    logic        act_swap;
    logic        result_swap;
    logic        result_accumulate;

    // Memory <-> Systolic_Arr
    act_t        w_rdata [N];
    act_t        a_rdata [N];
    acc_t        result_out_arr [N];

    // Post_Processor <-> Memory
    logic [7:0]  pp_r_addr;
    logic        pp_a_we;
    logic [7:0]  pp_a_waddr;
    act_t        pp_a_wdata [N];

    // Memory'nin host portlarina giden, secilmis sinyaller
    logic [7:0]  mem_r_raddr;
    logic        mem_a_we;
    logic [7:0]  mem_a_waddr;
    act_t        mem_a_wdata [N];

    acc_t        mem_r_rdata [N];     // Result_Buffer okuma verisi: hem host'a hem Post_Processor'a gider

    // ------------------------------------------------------------
    // Port secimi: Post_Processor calisirken (pp_busy) Result_Buffer'in okuma portunu ve
    // Act_Buffer'in yazma portunu o kullanir, degilse host kullanir.
    // Host, pp_busy iken bu portlara dokunmamali.
    // ------------------------------------------------------------
    assign mem_r_raddr = pp_busy ? pp_r_addr  : r_addr;
    assign mem_a_we    = pp_busy ? pp_a_we    : a_we;
    assign mem_a_waddr = pp_busy ? pp_a_waddr : a_addr;

    for (genvar i = 0; i < N; i++) begin : G_SEL
        assign mem_a_wdata[i] = pp_busy ? pp_a_wdata[i] : a_wdata[i];
        assign r_rdata[i]     = mem_r_rdata[i];
    end


    Sequencer seq(
        .clk        (clk),
        .rst_n      (rst_n),
        .start      (start),
        .accumulate (accumulate),
        .last_tile  (last_tile),
        .input_vector_count(input_vector_count),
        .weight_base(weight_base),
        .act_base   (act_base),
        .result_base(result_base),

        .busy(busy),
        .done(done),

        .mode(mode),
        .act_valid(act_valid),
        .result_valid(result_valid),

        .weight_raddr(weight_raddr),
        .act_raddr(act_raddr),
        .result_we(result_we),
        .result_waddr(result_waddr),
        .act_swap(act_swap),
        .result_swap(result_swap),
        .result_accumulate(result_accumulate)
    );

    Systolic_Arr arr(
        .clk(clk), .rst_n(rst_n),
        .mode(mode),
        .act_valid(act_valid),
        .act_feed_arr(a_rdata),
        .weight_feed_arr(w_rdata),
        .result_out_arr(result_out_arr),
        .result_valid(result_valid)
    );

    Post_Processor pp(
        .clk(clk), .rst_n(rst_n),
        .start(pp_start),
        .row_count(pp_row_count),
        .src_base(pp_src_base),
        .dst_base(pp_dst_base),
        .shift(pp_shift),
        .relu_en(pp_relu_en),
        .busy(pp_busy),
        .done(pp_done),
        .r_addr(pp_r_addr),
        .r_rdata(mem_r_rdata),
        .a_we(pp_a_we),
        .a_waddr(pp_a_waddr),
        .a_wdata(pp_a_wdata)
    );

    Memory mem(
        .clk(clk), .rst_n(rst_n),

        // agirlik: host yazar, sequencer adres verir, dizi okur
        .w_we(w_we),
        .w_waddr(w_addr),
        .w_wdata(w_wdata),
        .w_raddr(weight_raddr),
        .w_rdata(w_rdata),

        // girdi: host veya post-processor yazar, sequencer adres/swap verir, dizi okur
        .a_swap(act_swap),
        .a_we(mem_a_we),
        .a_waddr(mem_a_waddr),
        .a_wdata(mem_a_wdata),
        .a_raddr(act_raddr),
        .a_rdata(a_rdata),
        .a_compute_bank(),

        // sonuc: dizi yazar (sequencer adres/izin verir), host veya post-processor okur
        .r_swap(result_swap),
        .r_accumulate(result_accumulate),
        .r_we(result_we),
        .r_waddr(result_waddr),
        .r_wdata(result_out_arr),
        .r_raddr(mem_r_raddr),
        .r_rdata(mem_r_rdata),
        .r_write_bank()
    );


endmodule
