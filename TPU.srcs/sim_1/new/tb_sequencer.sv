`timescale 1ns / 1ps

// Sequencer + Memory + Systolic_Arr uctan uca self-checking testbench.
// Testbench "host" rolunu oynar: belleklere yazar, start verir, sonucu Result_Buffer'dan okur.
//   Kosu 0: M=20, bazlar (w=8,  a=16,  r=32)   -- calisirken sonraki girdi (kosu 1) fill bankasina yazilir
//   Kosu 1: M=5,  bazlar (w=0,  a=0,   r=0)    -- yeni agirlik; calisirken kosu 2'nin girdisi yazilir
//   Kosu 2: M=1,  bazlar (w=20, a=100, r=7)    -- en kucuk akis (sonuc tamamen DRAIN'de gelir)

module tb_sequencer;
    import general_pkg::*;

    localparam int RUNS = 3;
    localparam int MAXM = 20;
    localparam int MRUN [RUNS] = '{20, 5, 1};
    localparam int WB   [RUNS] = '{8, 0, 20};
    localparam int AB   [RUNS] = '{16, 0, 100};
    localparam int RB   [RUNS] = '{32, 0, 7};

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // host -> Memory
    logic       w_we;
    logic [5:0] w_waddr;
    act_t       w_wdata [N];
    logic       a_we;
    logic [7:0] a_waddr;
    act_t       a_wdata [N];
    logic [7:0] r_raddr;
    acc_t       r_rdata [N];

    // host -> Sequencer
    logic       start = 0;
    logic [8:0] input_vector_count = 0;
    logic [5:0] weight_base = 0;
    logic [7:0] act_base = 0, result_base = 0;
    logic       busy, done;

    // Sequencer <-> Memory / Systolic_Arr
    mode_t      mode;
    logic       act_valid, result_valid;
    logic [5:0] weight_raddr;
    logic [7:0] act_raddr, result_waddr;
    logic       result_we, act_swap, result_swap, result_accumulate;

    // Memory <-> Systolic_Arr
    act_t       w_rdata [N], a_rdata [N];
    acc_t       result_out_arr [N];
    logic       a_bank, r_bank;

    Memory mem (
        .clk(clk), .rst_n(rst_n),
        .w_we(w_we), .w_waddr(w_waddr), .w_wdata(w_wdata), .w_raddr(weight_raddr), .w_rdata(w_rdata),
        .a_swap(act_swap), .a_we(a_we), .a_waddr(a_waddr), .a_wdata(a_wdata), .a_raddr(act_raddr),
        .a_rdata(a_rdata), .a_compute_bank(a_bank),
        .r_swap(result_swap), .r_we(result_we), .r_waddr(result_waddr), .r_wdata(result_out_arr),
        .r_accumulate(result_accumulate), .r_raddr(r_raddr), .r_rdata(r_rdata), .r_write_bank(r_bank)
    );

    Systolic_Arr arr (
        .clk(clk), .rst_n(rst_n), .mode(mode), .act_valid(act_valid),
        .act_feed_arr(a_rdata), .weight_feed_arr(w_rdata),
        .result_out_arr(result_out_arr), .result_valid(result_valid)
    );

    Sequencer seq (
        .clk(clk), .rst_n(rst_n), .start(start), .input_vector_count(input_vector_count),
        .weight_base(weight_base), .act_base(act_base), .result_base(result_base),
        .busy(busy), .done(done), .mode(mode), .act_valid(act_valid), .result_valid(result_valid),
        .weight_raddr(weight_raddr), .act_raddr(act_raddr), .result_we(result_we),
        .result_waddr(result_waddr), .act_swap(act_swap), .result_swap(result_swap),
        .accumulate(1'b0), .last_tile(1'b1), .result_accumulate(result_accumulate)
    );

    act_t Wall [RUNS][N][N];
    act_t Aall [RUNS][MAXM][N];
    acc_t EXP  [RUNS][MAXM][N];
    int errors = 0, checked = 0, done_count = 0;

    always @(posedge clk) if (done) done_count++;

    task automatic gen_run(input int run, input int seed);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) Wall[run][i][j] = $urandom(seed + i*N + j) % 256 - 128;
        for (int t = 0; t < MRUN[run]; t++)
            for (int i = 0; i < N; i++) Aall[run][t][i] = $urandom(seed + 500 + t*N + i) % 256 - 128;
        for (int t = 0; t < MRUN[run]; t++)
            for (int j = 0; j < N; j++) begin
                EXP[run][t][j] = 0;
                for (int i = 0; i < N; i++) EXP[run][t][j] += Aall[run][t][i] * Wall[run][i][j];
            end
    endtask

    task automatic write_weights(input int run);
        for (int row = 0; row < N; row++) begin
            @(negedge clk);
            w_we = 1; w_waddr = WB[run] + row;
            for (int c = 0; c < N; c++) w_wdata[c] = Wall[run][row][c];
        end
        @(negedge clk); w_we = 0;
    endtask

    task automatic write_acts(input int run);
        for (int t = 0; t < MRUN[run]; t++) begin
            @(negedge clk);
            a_we = 1; a_waddr = AB[run] + t;
            for (int c = 0; c < N; c++) a_wdata[c] = Aall[run][t][c];
        end
        @(negedge clk); a_we = 0;
    endtask

    task automatic start_run(input int run);
        @(negedge clk);
        input_vector_count = MRUN[run]; weight_base = WB[run]; act_base = AB[run]; result_base = RB[run];
        start = 1;
        @(negedge clk);
        start = 0;
    endtask

    task automatic wait_done(input int run);
        int g = 0;
        while (done_count < run + 1 && g < 3000) begin @(posedge clk); g++; end
        if (done_count < run + 1) begin errors++; $display("MISMATCH run %0d: done never came (timeout)", run); end
        if (busy) begin errors++; $display("MISMATCH run %0d: busy still high after done", run); end
    endtask

    task automatic check_results(input int run);
        repeat (2) @(negedge clk);
        for (int t = 0; t < MRUN[run]; t++) begin
            r_raddr = RB[run] + t;
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (r_rdata[c] !== EXP[run][t][c]) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH run=%0d row=%0d c=%0d got=%0d exp=%0d", run, t, c, r_rdata[c], EXP[run][t][c]);
                end
            end
            @(negedge clk);
        end
    endtask

    initial begin
        w_we = 0; a_we = 0; w_waddr = 0; a_waddr = 0; r_raddr = 0;
        for (int c = 0; c < N; c++) begin w_wdata[c] = 0; a_wdata[c] = 0; end
        gen_run(0, 1); gen_run(1, 2000); gen_run(2, 9000);
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // ---- Kosu 0 ----
        write_weights(0);
        write_acts(0);
        start_run(0);
        repeat (3) @(negedge clk);
        write_acts(1);                 // calisirken bir sonraki girdi fill bankasina
        wait_done(0);
        check_results(0);

        // ---- Kosu 1 ----
        write_weights(1);
        start_run(1);
        repeat (3) @(negedge clk);
        write_acts(2);
        wait_done(1);
        check_results(1);

        // ---- Kosu 2 ----
        write_weights(2);
        start_run(2);
        wait_done(2);
        check_results(2);

        if (done_count != RUNS) begin errors++; $display("MISMATCH done_count=%0d exp=%0d", done_count, RUNS); end
        $display("RESULT: checked=%0d errors=%0d", checked, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
