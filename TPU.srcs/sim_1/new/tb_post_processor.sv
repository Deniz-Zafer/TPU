`timescale 1ns / 1ps

// Post_Processor + Memory testbench (gercek Result_Buffer ve Act_Buffer ile):
//   1) Result_Buffer'a ham 32 bit sonuclar yazilir ve swap ile okunabilir banka yapilir
//   2) Post_Processor satirlari okuyup ReLU / kaydir / sigdir ile Act_Buffer'a yazar
//   3) Act_Buffer swap edilip yazilan satirlar okunur, referans (clip(relu(x) >>> shift)) ile karsilastirilir

module tb_post_processor;
    import general_pkg::*;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    // Post_Processor
    logic        start = 0, relu_en = 0, busy, done;
    logic [8:0]  row_count = 0;
    logic [7:0]  src_base = 0, dst_base = 0;
    logic [4:0]  shift = 0;
    logic [7:0]  pp_r_addr, pp_a_waddr;
    logic        pp_a_we;
    acc_t        pp_r_rdata [N];
    act_t        pp_a_wdata [N];

    // Memory: Result_Buffer core yazma tarafi + Act_Buffer okuma tarafi testbench'ten
    logic        r_swap = 0, r_we = 0, a_swap = 0;
    logic [7:0]  r_waddr = 0, a_raddr = 0;
    acc_t        r_wdata [N];
    act_t        a_rdata [N];
    act_t        zero_w [N];

    Post_Processor pp (
        .clk(clk), .rst_n(rst_n), .start(start), .row_count(row_count),
        .src_base(src_base), .dst_base(dst_base), .shift(shift), .relu_en(relu_en),
        .busy(busy), .done(done),
        .r_addr(pp_r_addr), .r_rdata(pp_r_rdata),
        .a_we(pp_a_we), .a_waddr(pp_a_waddr), .a_wdata(pp_a_wdata)
    );

    Memory mem (
        .clk(clk), .rst_n(rst_n),
        .w_we(1'b0), .w_waddr('0), .w_wdata(zero_w), .w_raddr('0), .w_rdata(),
        .a_swap(a_swap), .a_we(pp_a_we), .a_waddr(pp_a_waddr), .a_wdata(pp_a_wdata),
        .a_raddr(a_raddr), .a_rdata(a_rdata), .a_compute_bank(),
        .r_swap(r_swap), .r_accumulate(1'b0), .r_we(r_we), .r_waddr(r_waddr), .r_wdata(r_wdata),
        .r_raddr(pp_r_addr), .r_rdata(pp_r_rdata), .r_write_bank()
    );

    int errors = 0, checked = 0, done_count = 0, write_count = 0;
    always @(posedge clk) begin
        if (done)    done_count++;
        if (pp_a_we) write_count++;
        if (pp_a_we && !busy) begin errors++; $display("MISMATCH a_we while idle"); end
    end

    function automatic int ref_f(int v, int sh, bit rl);
        int t = (rl && v < 0) ? 0 : v;
        t = t >>> sh;
        if (t > 127) return 127;
        if (t < -128) return -128;
        return t;
    endfunction

    int X [64][N];

    task automatic run_cfg(input int M, input int sb, input int db, input int sh, input bit rl, input int seed);
        int dc_before = done_count;
        int wc_before;
        // 1) ham sonuclari Result_Buffer'a yaz, swap ile okunabilir banka yap
        for (int t = 0; t < M; t++) begin
            @(negedge clk);
            r_we = 1; r_waddr = sb + t;
            for (int c = 0; c < N; c++) begin
                int v = $urandom(seed + t*N + c) % 2000000 - 1000000;
                if (((t + c) % 3) == 0) v = v % 300;
                X[t][c] = v;
                r_wdata[c] = v;
            end
        end
        @(negedge clk); r_we = 0;
        r_swap = 1; @(negedge clk); r_swap = 0;
        repeat (2) @(negedge clk);

        // 2) post-processor'u calistir
        wc_before = write_count;
        row_count = M; src_base = sb; dst_base = db; shift = sh; relu_en = rl;
        start = 1; @(negedge clk); start = 0;
        begin : WAIT
            int g = 0;
            while (done_count == dc_before && g < 1000) begin @(negedge clk); g++; end
            if (done_count == dc_before) begin errors++; $display("MISMATCH timeout waiting done"); end
        end
        @(negedge clk);
        if (busy) begin errors++; $display("MISMATCH busy high after done"); end
        if (write_count - wc_before != M) begin
            errors++; $display("MISMATCH write count=%0d exp=%0d", write_count - wc_before, M);
        end

        // 3) Act_Buffer'i swap et, yazilan satirlari oku ve karsilastir
        a_swap = 1; @(negedge clk); a_swap = 0;
        for (int t = 0; t < M; t++) begin
            a_raddr = db + t;
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (a_rdata[c] !== act_t'(ref_f(X[t][c], sh, rl))) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH M=%0d sh=%0d relu=%0b row=%0d c=%0d x=%0d got=%0d exp=%0d",
                                              M, sh, rl, t, c, X[t][c], a_rdata[c], ref_f(X[t][c], sh, rl));
                end
            end
            @(negedge clk);
        end
    endtask

    initial begin
        for (int c = 0; c < N; c++) begin zero_w[c] = 0; r_wdata[c] = 0; end
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        run_cfg(12,  4, 10,  6, 1,  100);   // ReLU acik
        run_cfg(12,  4, 10,  6, 0,  200);   // ReLU kapali
        run_cfg( 1,  0,  3,  0, 1,  300);   // tek satir, kaydirma yok
        run_cfg(20, 30, 50, 12, 0,  400);   // buyuk kaydirma, ReLU kapali
        run_cfg( 7,  9, 99,  3, 1,  500);   // kucuk kaydirma (cogu sigdirilir)

        if (done_count != 5) begin errors++; $display("MISMATCH done_count=%0d exp=5", done_count); end
        $display("RESULT: checked=%0d errors=%0d", checked, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
