`timescale 1ns / 1ps

// Post_Processor: Result_Buffer'daki biten sonuc satirlarini (8 x 32 bit) okur,
// her lane icin  ReLU -> aritmetik saga kaydirma -> [-128,127]'ye sigdirma  uygular,
// 8 x 8 bit olarak Act_Buffer'in fill bankasina yazar (sonraki katmanin girdisi).
//
//   IDLE -> RUN (M cycle: her cycle bir satir icin adres ver) -> FLUSH (son satirin yazilmasi) -> DONE -> IDLE
//
// Bellek 1 cycle gec cevap verir: veri, adresten 1 cycle sonra gelir. Bu yuzden
// yazma izni (a_we) ve yazma adresi (a_waddr), adres sinyallerinin 1 cycle gecikmeli kopyasidir.

module Post_Processor
    import general_pkg::*;
#(
    parameter int A_DEPTH = 256,    // Act_Buffer satir sayisi (banka basina)
    parameter int R_DEPTH = 256     // Result_Buffer satir sayisi (banka basina)
)(
    input  logic                        clk, rst_n,

    // host / kontrol
    input  logic                        start,
    input  logic [$clog2(A_DEPTH):0]    row_count,
    input  logic [$clog2(R_DEPTH)-1:0]  src_base,
    input  logic [$clog2(A_DEPTH)-1:0]  dst_base,
    input  logic [4:0]                  shift,
    input  logic                        relu_en,
    output logic                        busy, done,

    // Result_Buffer (okuma)
    output logic [$clog2(R_DEPTH)-1:0]  r_addr,
    input  acc_t                        r_rdata [N],        // 32 bit x N

    // Act_Buffer (yazma)
    output logic                        a_we,
    output logic [$clog2(A_DEPTH)-1:0]  a_waddr,
    output act_t                        a_wdata [N]         // 8 bit x N
);

    localparam int A_AW = $clog2(A_DEPTH);
    localparam int R_AW = $clog2(R_DEPTH);

    typedef enum logic [2:0] {
        STATE_IDLE  = 3'b000,
        STATE_RUN   = 3'b001,
        STATE_FLUSH = 3'b010,
        STATE_DONE  = 3'b011
    } state_t;

    state_t                 state;
    logic [A_AW:0]          cnt;             // RUN'da kacinci satir icin adres veriyoruz
    logic [A_AW:0]          row_count_q;
    logic [R_AW-1:0]        src_base_q;
    logic [A_AW-1:0]        dst_base_q;
    logic [4:0]             shift_q;
    logic                   relu_q;

    // ------------------------------------------------------------
    // 1) Durum makinesi + sayac (donguyu sayac yapar, for degil)
    // ------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= STATE_IDLE;
            cnt         <= '0;
            row_count_q <= '0;
            src_base_q  <= '0;
            dst_base_q  <= '0;
            shift_q     <= '0;
            relu_q      <= 1'b0;
        end else begin
            case (state)
                STATE_IDLE: begin
                    cnt <= '0;
                    if (start && row_count != '0) begin
                        row_count_q <= row_count;
                        src_base_q  <= src_base;
                        dst_base_q  <= dst_base;
                        shift_q     <= shift;
                        relu_q      <= relu_en;
                        state       <= STATE_RUN;
                    end
                end

                STATE_RUN: begin
                    if (cnt == row_count_q - 1'b1) begin
                        cnt   <= '0;
                        state <= STATE_FLUSH;     // son satirin yazilmasi icin 1 cycle
                    end else begin
                        cnt <= cnt + 1'b1;
                    end
                end

                STATE_FLUSH: state <= STATE_DONE;

                STATE_DONE:  state <= STATE_IDLE;

                default:     state <= STATE_IDLE;
            endcase
        end
    end

    assign busy = (state != STATE_IDLE);
    assign done = (state == STATE_DONE);

    // ------------------------------------------------------------
    // 2) Bellek gecikmesi: veriyle birlikte giden sinyaller adresin 1 cycle gecikmisi
    // ------------------------------------------------------------
    logic          valid_q;
    logic [A_AW:0] cnt_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_q <= 1'b0;
            cnt_q   <= '0;
        end else begin
            valid_q <= (state == STATE_RUN);
            cnt_q   <= cnt;
        end
    end

    assign r_addr  = src_base_q + R_AW'(cnt);
    assign a_we    = valid_q;
    assign a_waddr = dst_base_q + A_AW'(cnt_q);

    // ------------------------------------------------------------
    // 3) Veri yolu: 8 lane paralel  ReLU -> >>> shift -> sigdir  (kombinasyonel)
    // ------------------------------------------------------------
    for (genvar i = 0; i < N; i++) begin : G_LANE
        acc_t relu_v, shifted;
        assign relu_v     = (relu_q && r_rdata[i] < 0) ? '0 : r_rdata[i];
        assign shifted    = relu_v >>> shift_q;
        assign a_wdata[i] = (shifted >  127) ? 8'sd127  :
                            (shifted < -128) ? -8'sd128 : shifted[ACT_W-1:0];
    end

endmodule
