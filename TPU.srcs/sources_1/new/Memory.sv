`timescale 1ns / 1ps

// ============================================================
// Simple_RAM: 1 yazma + 1 okuma kapisi, senkron okuma (1 cycle gecikme)
// Ayni adrese ayni cycle'da yazma+okuma olursa okuma ESKI degeri verir.
// Bellek reset'lenmez: yazilmamis satirlar sim'de X okunur.
// ============================================================
// accumulate=1 iken yazma "uzerine yaz" degil "eski degere ekle" olur.
// Ekleme SUTUN SUTUN yapilir (LANE_W bit'lik parcalar): bir sutundan tasan elde
// yandaki sutuna gecmesin diye. Biriktirme kullanilmayacaksa LANE_W = WIDTH birakilir.
module Simple_RAM #(
    parameter int WIDTH  = 64,
    parameter int LANE_W = WIDTH,
    parameter int DEPTH  = 64
)(
    input  logic                      clk,
    input  logic                      we,
    input  logic                      accumulate,
    input  logic [$clog2(DEPTH)-1:0]  waddr,
    input  logic [WIDTH-1:0]          wdata,
    input  logic [$clog2(DEPTH)-1:0]  raddr,
    output logic [WIDTH-1:0]          rdata
);

    logic [WIDTH-1:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        if (we) begin
            if (!accumulate) begin
                mem[waddr] <= wdata;
            end else begin
                for (int l = 0; l < WIDTH/LANE_W; l++)
                    mem[waddr][l*LANE_W +: LANE_W] <= mem[waddr][l*LANE_W +: LANE_W]
                                                    + wdata[l*LANE_W +: LANE_W];
            end
        end
        rdata <= mem[raddr];
    end

endmodule


// ============================================================
// Weight_Buffer: agirlik tablosu (tek banka)
//   Yazma  : disaridan (host / testbench)   -> we, waddr, wdata
//   Okuma  : sequencer sayaci -> raddr, rdata (1 cycle sonra gelir)
// Her satir = N agirlik (N x 8 bit). LOAD sirasinda satir N-1'den 0'a okunur.
// ============================================================
module Weight_Buffer
    import general_pkg::*;
#(
    parameter int DEPTH = 64
)(
    input  logic                      clk,

    input  logic                      we,
    input  logic [$clog2(DEPTH)-1:0]  waddr,
    input  logic signed [ACT_W-1:0]   wdata [N],      // 8 bit x N

    input  logic [$clog2(DEPTH)-1:0]  raddr,
    output logic signed [ACT_W-1:0]   rdata [N]       // 8 bit x N
);

    logic [N*ACT_W-1:0] wword, rword;

    for (genvar i = 0; i < N; i++) begin : G_PACK
        assign wword[i*ACT_W +: ACT_W] = wdata[i];
        assign rdata[i]                = rword[i*ACT_W +: ACT_W];
    end

    Simple_RAM #(.WIDTH(N*ACT_W), .DEPTH(DEPTH)) ram (
        .clk  (clk),
        .we   (we),
        .waddr(waddr),
        .wdata(wword),
        .raddr(raddr),
        .rdata(rword),
        .accumulate(1'b0)
    );

endmodule


// ============================================================
// Act_Buffer: girdi (aktivasyon) tablosu, PING-PONG (2 banka)
//   sel = "compute bankasi" (dizi buradan okur)
//   ~sel = "fill bankasi"   (host buraya yazar)
//   swap darbesi gelince roller yer degistirir.
//
//   Yazma (host)  : we, waddr, wdata  -> HER ZAMAN fill bankasina gider
//   Okuma (dizi)  : raddr, rdata      -> HER ZAMAN compute bankasindan gelir (1 cycle sonra)
//
// Kural: swap'i compute akisi (STREAM) sirasinda verme.
// ============================================================
module Act_Buffer
    import general_pkg::*;
#(
    parameter int DEPTH = 256
)(
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      swap,

    input  logic                      we,
    input  logic [$clog2(DEPTH)-1:0]  waddr,
    input  logic signed [ACT_W-1:0]   wdata [N],      // 8 bit x N

    input  logic [$clog2(DEPTH)-1:0]  raddr,
    output logic signed [ACT_W-1:0]   rdata [N],      // 8 bit x N

    output logic                      compute_bank
);

    logic sel, sel_q;
    assign compute_bank = sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel   <= 1'b0;
            sel_q <= 1'b0;
        end else begin
            if (swap) sel <= ~sel;
            sel_q <= sel;        // okuma verisiyle ayni cycle'a hizali secim
        end
    end

    logic [N*ACT_W-1:0] wword;
    logic [N*ACT_W-1:0] rword [2];
    logic [N*ACT_W-1:0] rword_sel;

    for (genvar i = 0; i < N; i++) begin : G_PACK
        assign wword[i*ACT_W +: ACT_W] = wdata[i];
        assign rdata[i]                = rword_sel[i*ACT_W +: ACT_W];
    end

    assign rword_sel = sel_q ? rword[1] : rword[0];

    for (genvar b = 0; b < 2; b++) begin : G_BANK
        Simple_RAM #(.WIDTH(N*ACT_W), .DEPTH(DEPTH)) bank (
            .clk  (clk),
            .we   (we && (sel != b[0])),    // fill bankasi = ~sel
            .waddr(waddr),
            .wdata(wword),
            .raddr(raddr),
            .rdata(rword[b]),
            .accumulate(1'b0)
        );
    end

endmodule


// ============================================================
// Result_Buffer: sonuc tablosu, PING-PONG (2 banka)
//   sel = "yazma bankasi" (dizi sonuclari buraya yazar)
//   ~sel = "okuma bankasi" (host bir onceki islemin sonuclarini buradan okur)
//   swap darbesi (islem bitince) rolleri degistirir.
//
//   Yazma (dizi/de-skew cikisi) : we, waddr, wdata -> yazma bankasina
//   Okuma (host)                : raddr, rdata     -> okuma bankasindan (1 cycle sonra)
// ============================================================
module Result_Buffer
    import general_pkg::*;
#(
    parameter int DEPTH = 256
)(
    input  logic                      clk,
    input  logic                      rst_n,

    input  logic                      swap,
    
    input  logic                      accumulate,

    input  logic                      we,
    input  logic [$clog2(DEPTH)-1:0]  waddr,
    input  logic signed [ACC_W-1:0]   wdata [N],      // 32 bit x N

    input  logic [$clog2(DEPTH)-1:0]  raddr,
    output logic signed [ACC_W-1:0]   rdata [N],      // 32 bit x N

    output logic                      write_bank
);

    logic sel, rd_bank_q;
    assign write_bank = sel;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sel       <= 1'b0;
            rd_bank_q <= 1'b1;
        end else begin
            if (swap) sel <= ~sel;
            rd_bank_q <= ~sel;   // host'un okudugu banka (~sel), 1 cycle gecikmeli
        end
    end

    logic [N*ACC_W-1:0] wword;
    logic [N*ACC_W-1:0] rword [2];
    logic [N*ACC_W-1:0] rword_sel;

    for (genvar i = 0; i < N; i++) begin : G_PACK
        assign wword[i*ACC_W +: ACC_W] = wdata[i];
        assign rdata[i]                = rword_sel[i*ACC_W +: ACC_W];
    end

    assign rword_sel = rd_bank_q ? rword[1] : rword[0];

    for (genvar b = 0; b < 2; b++) begin : G_BANK
        Simple_RAM #(.WIDTH(N*ACC_W), .LANE_W(ACC_W), .DEPTH(DEPTH)) bank (
            .clk  (clk),
            .we   (we && (sel == b[0])),    // yazma bankasi = sel
            .waddr(waddr),
            .wdata(wword),
            .raddr(raddr),
            .rdata(rword[b]),
            .accumulate(accumulate)
        );
    end

endmodule


// ============================================================
// Memory: 3 buffer'i tek modulde toplayan sarmalayici
//
//   HOST tarafi : disaridan (testbench / CSR / DMA) bellekleri doldurur, sonucu okur
//   CORE tarafi : sequencer + sistolik dizi adres verir, veri alir / yazar
//
//   Weight_Buffer : host yazar            -> core okur   (agirlik tablosu, tek banka)
//   Act_Buffer    : host yazar            -> core okur   (girdi tablosu, ping-pong)
//   Result_Buffer : core yazar            -> host okur   (sonuc tablosu, ping-pong)
//
//   Tum okumalar 1 cycle gecikmeli. swap darbeleri sequencer'dan gelir (islem bitince).
// ============================================================
module Memory
    import general_pkg::*;
#(
    parameter int W_DEPTH = 64,     // Weight_Buffer satir sayisi
    parameter int A_DEPTH = 256,    // Act_Buffer satir sayisi (banka basina)
    parameter int R_DEPTH = 256     // Result_Buffer satir sayisi (banka basina)
)(
    input  logic                       clk,
    input  logic                       rst_n,

    // ---------------- Weight_Buffer ----------------
    // HOST: yazma
    input  logic                       w_we,
    input  logic [$clog2(W_DEPTH)-1:0] w_waddr,
    input  logic signed [ACT_W-1:0]    w_wdata [N],          // 8 bit x N
    // CORE: okuma (LOAD sirasinda satir N-1'den 0'a)
    input  logic [$clog2(W_DEPTH)-1:0] w_raddr,
    output logic signed [ACT_W-1:0]    w_rdata [N],          // 8 bit x N

    // ---------------- Act_Buffer (ping-pong) ----------------
    input  logic                       a_swap,
    // HOST: yazma (fill bankasina)
    input  logic                       a_we,
    input  logic [$clog2(A_DEPTH)-1:0] a_waddr,
    input  logic signed [ACT_W-1:0]    a_wdata [N],          // 8 bit x N
    // CORE: okuma (compute bankasindan)
    input  logic [$clog2(A_DEPTH)-1:0] a_raddr,
    output logic signed [ACT_W-1:0]    a_rdata [N],          // 8 bit x N
    output logic                       a_compute_bank,

    // ---------------- Result_Buffer (ping-pong) ----------------
    input  logic                       r_swap,
    input  logic                       r_accumulate,         // 1: yazma = eski degere ekle
    // CORE: yazma (yazma bankasina)
    input  logic                       r_we,
    input  logic [$clog2(R_DEPTH)-1:0] r_waddr,
    input  logic signed [ACC_W-1:0]    r_wdata [N],          // 32 bit x N
    // HOST: okuma (bir onceki islemin sonuclari)
    input  logic [$clog2(R_DEPTH)-1:0] r_raddr,
    output logic signed [ACC_W-1:0]    r_rdata [N],          // 32 bit x N
    output logic                       r_write_bank
);

    Weight_Buffer #(.DEPTH(W_DEPTH)) weight_buf (
        .clk  (clk),
        .we   (w_we),
        .waddr(w_waddr),
        .wdata(w_wdata),
        .raddr(w_raddr),
        .rdata(w_rdata)
    );

    Act_Buffer #(.DEPTH(A_DEPTH)) act_buf (
        .clk         (clk),
        .rst_n       (rst_n),
        .swap        (a_swap),
        .we          (a_we),
        .waddr       (a_waddr),
        .wdata       (a_wdata),
        .raddr       (a_raddr),
        .rdata       (a_rdata),
        .compute_bank(a_compute_bank)
    );

    Result_Buffer #(.DEPTH(R_DEPTH)) result_buf (
        .clk       (clk),
        .rst_n     (rst_n),
        .swap      (r_swap),
        .we        (r_we),
        .waddr     (r_waddr),
        .wdata     (r_wdata),
        .raddr     (r_raddr),
        .rdata     (r_rdata),
        .write_bank(r_write_bank),
        .accumulate(r_accumulate)
    );

endmodule
