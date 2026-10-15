`timescale 1ns / 1ps

// Iki katmanli ag testi, sadece TPU_Core portlariyla (host gibi):
//   Katman 1:  Y1 = A1 @ W1                      (TPU_Core calisir, sonuc Result_Buffer'da)
//   Ara adim:  X2 = clip( relu(Y1) >>> shift )   (Post_Processor: Result_Buffer -> Act_Buffer)
//   Katman 2:  Y2 = X2 @ W2                      (TPU_Core calisir, girdi dogrudan Act_Buffer'dan)
// Y2, testbench'te hesaplanan referansla karsilastirilir. 3 senaryo art arda kosulur.

module tb_layers;
    import general_pkg::*;

    localparam int NNETS = 3;
    localparam int MAXM  = 12;
    localparam int NET_M     [NNETS] = '{10, 6, 1};
    localparam int NET_SHIFT [NNETS] = '{8, 9, 8};
    localparam bit NET_RELU  [NNETS] = '{1, 0, 1};

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // TPU_Core portlari
    logic       start = 0, accumulate = 0, last_tile = 1;
    logic [8:0] input_vector_count = 0;
    logic [5:0] weight_base = 0;
    logic [7:0] act_base = 0, result_base = 0;
    logic       busy, done;
    logic       w_we = 0, a_we = 0;
    logic [5:0] w_addr = 0;
    logic [7:0] a_addr = 0, r_addr = 0;
    act_t       w_wdata [N], a_wdata [N];
    acc_t       r_rdata [N];
    logic       pp_start = 0, pp_relu_en = 0, pp_busy, pp_done;
    logic [8:0] pp_row_count = 0;
    logic [7:0] pp_src_base = 0, pp_dst_base = 0;
    logic [4:0] pp_shift = 0;

    TPU_Core dut (.clk(clk), .rst_n(rst_n), .start(start), .input_vector_count(input_vector_count),
        .weight_base(weight_base), .act_base(act_base), .result_base(result_base),
        .accumulate(accumulate), .last_tile(last_tile), .busy(busy), .done(done),
        .w_we(w_we), .w_addr(w_addr), .w_wdata(w_wdata),
        .a_we(a_we), .a_addr(a_addr), .a_wdata(a_wdata),
        .r_addr(r_addr), .r_rdata(r_rdata),
        .pp_start(pp_start), .pp_row_count(pp_row_count), .pp_src_base(pp_src_base),
        .pp_dst_base(pp_dst_base), .pp_shift(pp_shift), .pp_relu_en(pp_relu_en),
        .pp_busy(pp_busy), .pp_done(pp_done));

    int errors = 0, checked = 0, done_count = 0, pp_done_count = 0;
    always @(posedge clk) begin
        if (done)    done_count++;
        if (pp_done) pp_done_count++;
    end

    act_t W1 [N][N], W2 [N][N], A1 [MAXM][N];
    int   Y1 [MAXM][N], X2 [MAXM][N], Y2 [MAXM][N];

    function automatic int post_f(int v, int sh, bit rl);
        int t = (rl && v < 0) ? 0 : v;
        t = t >>> sh;
        if (t > 127) return 127;
        if (t < -128) return -128;
        return t;
    endfunction

    task automatic gen_net(input int n, input int seed);
        int M = NET_M[n];
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) begin
                W1[i][j] = $urandom(seed + i*N + j) % 256 - 128;
                W2[i][j] = $urandom(seed + 700 + i*N + j) % 256 - 128;
            end
        for (int t = 0; t < M; t++)
            for (int i = 0; i < N; i++) A1[t][i] = $urandom(seed + 1500 + t*N + i) % 256 - 128;
        for (int t = 0; t < M; t++)
            for (int j = 0; j < N; j++) begin
                Y1[t][j] = 0;
                for (int i = 0; i < N; i++) Y1[t][j] += A1[t][i] * W1[i][j];
                X2[t][j] = post_f(Y1[t][j], NET_SHIFT[n], NET_RELU[n]);
            end
        for (int t = 0; t < M; t++)
            for (int j = 0; j < N; j++) begin
                Y2[t][j] = 0;
                for (int i = 0; i < N; i++) Y2[t][j] += X2[t][i] * W2[i][j];
            end
    endtask

    task automatic write_weights(input bit second);
        for (int row = 0; row < N; row++) begin
            @(negedge clk);
            w_we = 1; w_addr = row;
            for (int c = 0; c < N; c++) w_wdata[c] = second ? W2[row][c] : W1[row][c];
        end
        @(negedge clk); w_we = 0;
    endtask

    task automatic write_inputs(input int M);
        for (int t = 0; t < M; t++) begin
            @(negedge clk);
            a_we = 1; a_addr = t;
            for (int c = 0; c < N; c++) a_wdata[c] = A1[t][c];
        end
        @(negedge clk); a_we = 0;
    endtask

    task automatic run_layer(input int M, input int abase, input int rbase);
        int dc = done_count;
        int g = 0;
        @(negedge clk);
        input_vector_count = M; weight_base = 0; act_base = abase; result_base = rbase;
        accumulate = 0; last_tile = 1; start = 1;
        @(negedge clk); start = 0;
        while (done_count == dc && g < 3000) begin @(negedge clk); g++; end
        if (done_count == dc) begin errors++; $display("MISMATCH layer timeout"); end
        @(negedge clk);
    endtask

    task automatic run_pp(input int M, input int sbase, input int dbase, input int sh, input bit rl);
        int pc = pp_done_count;
        int g = 0;
        @(negedge clk);
        pp_row_count = M; pp_src_base = sbase; pp_dst_base = dbase; pp_shift = sh; pp_relu_en = rl;
        pp_start = 1;
        @(negedge clk); pp_start = 0;
        while (pp_done_count == pc && g < 1000) begin @(negedge clk); g++; end
        if (pp_done_count == pc) begin errors++; $display("MISMATCH post-processor timeout"); end
        @(negedge clk);
    endtask

    task automatic check_layer2(input int n, input int rbase);
        int M = NET_M[n];
        repeat (2) @(negedge clk);
        for (int t = 0; t < M; t++) begin
            r_addr = rbase + t;
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (r_rdata[c] !== Y2[t][c]) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH net=%0d row=%0d c=%0d got=%0d exp=%0d", n, t, c, r_rdata[c], Y2[t][c]);
                end
            end
            @(negedge clk);
        end
    endtask

    initial begin
        for (int c = 0; c < N; c++) begin w_wdata[c] = 0; a_wdata[c] = 0; end
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        for (int n = 0; n < NNETS; n++) begin
            gen_net(n, 1000 * (n + 1));
            // Katman 1
            write_weights(0);
            write_inputs(NET_M[n]);
            run_layer(NET_M[n], 0, 0);
            // Ara adim: Result_Buffer[0..M-1] -> ReLU/requant -> Act_Buffer[20..]
            run_pp(NET_M[n], 0, 20, NET_SHIFT[n], NET_RELU[n]);
            // Katman 2: girdi dogrudan Act_Buffer'dan (host tekrar veri yazmaz)
            write_weights(1);
            run_layer(NET_M[n], 20, 40);
            check_layer2(n, 40);
        end

        if (done_count != 2 * NNETS || pp_done_count != NNETS) begin
            errors++; $display("MISMATCH done_count=%0d pp_done_count=%0d", done_count, pp_done_count);
        end
        $display("RESULT: checked=%0d errors=%0d", checked, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
