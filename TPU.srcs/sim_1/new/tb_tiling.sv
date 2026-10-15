`timescale 1ns / 1ps

// Tiling (K > 8) uctan uca testi: Sequencer + Memory + Systolic_Arr.
//   Her "is" (job) = K yonunde T tile. Tile'lar ayni result_base'e BIRIKTIRILIR
//   (ilk tile accumulate=0, sonrakiler accumulate=1; result_swap sadece son tile'da).
//   Host, calisan tile'in girdisinden sonraki tile'in girdisini fill bankasina onceden yazar.
//
//   Is 0: K=16 (2 tile), M=10          Is 3: K=8  (1 tile), M=1
//   Is 1: K=24 (3 tile), M=7           Is 4: K=32 (4 tile), M=5
//   Is 2: K=16 (2 tile), M=20 (sonuclar STREAM bitmeden gelmeye baslar)

module tb_tiling;
    import general_pkg::*;

    localparam int NJOBS = 5;
    localparam int MAXM  = 20;
    localparam int JOB_T  [NJOBS] = '{2, 3, 2, 1, 4};
    localparam int JOB_M  [NJOBS] = '{10, 7, 20, 1, 5};
    localparam int JOB_RB [NJOBS] = '{0, 40, 100, 7, 60};
    localparam int RUNS = 12;                       // 2+3+2+1+4

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // host -> Memory
    logic       w_we, a_we;
    logic [5:0] w_waddr;
    logic [7:0] a_waddr, r_raddr;
    act_t       w_wdata [N], a_wdata [N];
    acc_t       r_rdata [N];

    // host -> Sequencer
    logic       start = 0, accumulate = 0, last_tile = 0;
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

    act_t       w_rdata [N], a_rdata [N];
    acc_t       result_out_arr [N];
    logic       a_bank, r_bank;

    Memory mem (
        .clk(clk), .rst_n(rst_n),
        .w_we(w_we), .w_waddr(w_waddr), .w_wdata(w_wdata), .w_raddr(weight_raddr), .w_rdata(w_rdata),
        .a_swap(act_swap), .a_we(a_we), .a_waddr(a_waddr), .a_wdata(a_wdata), .a_raddr(act_raddr),
        .a_rdata(a_rdata), .a_compute_bank(a_bank),
        .r_swap(result_swap), .r_accumulate(result_accumulate), .r_we(result_we), .r_waddr(result_waddr),
        .r_wdata(result_out_arr), .r_raddr(r_raddr), .r_rdata(r_rdata), .r_write_bank(r_bank)
    );

    Systolic_Arr arr (
        .clk(clk), .rst_n(rst_n), .mode(mode), .act_valid(act_valid),
        .act_feed_arr(a_rdata), .weight_feed_arr(w_rdata),
        .result_out_arr(result_out_arr), .result_valid(result_valid)
    );

    Sequencer seq (
        .clk(clk), .rst_n(rst_n), .start(start), .accumulate(accumulate), .last_tile(last_tile),
        .input_vector_count(input_vector_count), .weight_base(weight_base), .act_base(act_base),
        .result_base(result_base), .busy(busy), .done(done), .mode(mode), .act_valid(act_valid),
        .result_valid(result_valid), .weight_raddr(weight_raddr), .act_raddr(act_raddr),
        .result_we(result_we), .result_waddr(result_waddr), .act_swap(act_swap),
        .result_swap(result_swap), .result_accumulate(result_accumulate)
    );

    // Kosu tablosu
    int   run_job  [RUNS];
    int   run_tile [RUNS];
    int   run_wb   [RUNS];
    int   run_ab   [RUNS];
    act_t Wt [RUNS][N][N];
    act_t At [RUNS][MAXM][N];
    acc_t EXPJ [NJOBS][MAXM][N];

    int errors = 0, checked = 0, done_count = 0;
    always @(posedge clk) if (done) done_count++;

    task automatic build_tables();
        int r = 0;
        for (int j = 0; j < NJOBS; j++) begin
            for (int t = 0; t < MAXM; t++)
                for (int c = 0; c < N; c++) EXPJ[j][t][c] = 0;
            for (int k = 0; k < JOB_T[j]; k++) begin
                run_job[r] = j; run_tile[r] = k;
                run_wb[r]  = (r % 3) * 8;       // tabanlar degissin diye
                run_ab[r]  = (r % 2) * 30;
                for (int i = 0; i < N; i++)
                    for (int c = 0; c < N; c++) Wt[r][i][c] = $urandom(r*1000 + i*N + c) % 256 - 128;
                for (int t = 0; t < JOB_M[j]; t++)
                    for (int i = 0; i < N; i++) At[r][t][i] = $urandom(r*1000 + 500 + t*N + i) % 256 - 128;
                for (int t = 0; t < JOB_M[j]; t++)
                    for (int c = 0; c < N; c++)
                        for (int i = 0; i < N; i++)
                            EXPJ[j][t][c] += At[r][t][i] * Wt[r][i][c];
                r++;
            end
        end
    endtask

    task automatic write_weights(input int r);
        for (int row = 0; row < N; row++) begin
            @(negedge clk);
            w_we = 1; w_waddr = run_wb[r] + row;
            for (int c = 0; c < N; c++) w_wdata[c] = Wt[r][row][c];
        end
        @(negedge clk); w_we = 0;
    endtask

    task automatic write_acts(input int r);
        for (int t = 0; t < JOB_M[run_job[r]]; t++) begin
            @(negedge clk);
            a_we = 1; a_waddr = run_ab[r] + t;
            for (int c = 0; c < N; c++) a_wdata[c] = At[r][t][c];
        end
        @(negedge clk); a_we = 0;
    endtask

    task automatic start_run(input int r);
        int j = run_job[r];
        @(negedge clk);
        input_vector_count = JOB_M[j]; weight_base = run_wb[r]; act_base = run_ab[r];
        result_base = JOB_RB[j];
        accumulate = (run_tile[r] != 0);
        last_tile  = (run_tile[r] == JOB_T[j] - 1);
        start = 1;
        @(negedge clk);
        start = 0;
    endtask

    task automatic wait_done(input int r);
        int g = 0;
        while (done_count < r + 1 && g < 3000) begin @(posedge clk); g++; end
        if (done_count < r + 1) begin errors++; $display("MISMATCH run %0d: done never came (timeout)", r); end
        if (busy) begin errors++; $display("MISMATCH run %0d: busy still high after done", r); end
    endtask

    task automatic check_job(input int j);
        repeat (2) @(negedge clk);
        for (int t = 0; t < JOB_M[j]; t++) begin
            r_raddr = JOB_RB[j] + t;
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (r_rdata[c] !== EXPJ[j][t][c]) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH job=%0d row=%0d c=%0d got=%0d exp=%0d", j, t, c, r_rdata[c], EXPJ[j][t][c]);
                end
            end
            @(negedge clk);
        end
    endtask

    initial begin
        w_we = 0; a_we = 0; w_waddr = 0; a_waddr = 0; r_raddr = 0;
        for (int c = 0; c < N; c++) begin w_wdata[c] = 0; a_wdata[c] = 0; end
        build_tables();
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        write_acts(0);
        for (int r = 0; r < RUNS; r++) begin
            write_weights(r);
            start_run(r);
            repeat (3) @(negedge clk);
            if (r + 1 < RUNS) write_acts(r + 1);       // sonraki tile'in girdisi calisirken fill bankasina
            wait_done(r);
            if (run_tile[r] == JOB_T[run_job[r]] - 1) check_job(run_job[r]);
        end

        if (done_count != RUNS) begin errors++; $display("MISMATCH done_count=%0d exp=%0d", done_count, RUNS); end
        $display("RESULT: checked=%0d errors=%0d", checked, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
