`timescale 1ns / 1ps

// Systolic_Arr self-checking testbench
//  - Tur 1: LOAD + kesintisiz akis
//  - Tur 2: LOAD'SUZ (agirlik HOLD'da korunuyor) + rastgele HOLD'lu akis
//  - Tur 3: yeni agirlik + HOLD'lu akis
//  - act_valid=0 iken giris portuna X basiliyor: dizinin icine X girmemeli
//  - Sonuclar sirayla (satir 0..M-1) ve tam 2N-1 ilerleme kenari sonra gelmeli

module tb_systolic_arr;
    import general_pkg::*;

    localparam int M = 20;

    logic  clk = 0, rst_n = 0, act_valid = 0, result_valid;
    mode_t mode = MODE_HOLD;
    act_t  act_feed_arr [N];
    act_t  weight_feed_arr [N];
    acc_t  result_out_arr [N];

    Systolic_Arr dut (.*);

    always #5 clk = ~clk;

    act_t W [N][N];
    act_t A [M][N];
    acc_t EXP [M][N];
    int errors = 0, checked = 0, nv = 0, ce = 0;

    task automatic gen_w(input int seed);
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++) W[i][j] = $urandom(seed + i*N + j) % 256 - 128;
    endtask

    task automatic gen_a(input int seed);
        for (int t = 0; t < M; t++)
            for (int i = 0; i < N; i++) A[t][i] = $urandom(seed + t*N + i) % 256 - 128;
        for (int t = 0; t < M; t++)
            for (int j = 0; j < N; j++) begin
                EXP[t][j] = 0;
                for (int i = 0; i < N; i++) EXP[t][j] += A[t][i] * W[i][j];
            end
    endtask

    task automatic junk_feed();
        for (int r = 0; r < N; r++) act_feed_arr[r] = 'x;
    endtask

    task automatic check_no_x();
        for (int r = 0; r < N; r++)
            if ($isunknown(dut.act_feed[r])) begin
                errors++; $display("MISMATCH X reached array row %0d", r);
            end
    endtask

    // Donanimin bir sonraki kenarda yakalayacagi cikisi orneklerir
    task automatic sample(input int completed);
        if (result_valid) begin
            if (nv >= M) begin
                errors++; $display("MISMATCH extra valid (nv=%0d)", nv);
            end else begin
                if (nv == 0 && completed != 2*N - 1) begin
                    errors++; $display("MISMATCH first valid after %0d compute edges, exp %0d", completed, 2*N-1);
                end
                for (int c = 0; c < N; c++) begin
                    checked++;
                    if (result_out_arr[c] !== EXP[nv][c]) begin
                        errors++;
                        if (errors < 10) $display("MISMATCH row=%0d c=%0d got=%0d exp=%0d", nv, c, result_out_arr[c], EXP[nv][c]);
                    end
                end
                nv++;
            end
        end
    endtask

    task automatic do_load();
        for (int k = 0; k < N; k++) begin
            @(negedge clk);
            mode = MODE_LOAD; act_valid = 0;
            for (int c = 0; c < N; c++) weight_feed_arr[c] = W[N-1-k][c];
            junk_feed();
            #1;
            if (result_valid) begin errors++; $display("MISMATCH valid during LOAD"); end
        end
    endtask

    task automatic hold_ticks(input int n);
        repeat (n) begin
            @(negedge clk);
            mode = MODE_HOLD; act_valid = 0;
            junk_feed();
            #1;
            if (result_valid) begin errors++; $display("MISMATCH valid during HOLD"); end
        end
    endtask

    task automatic run_stream(input bit holds);
        int tf = 0, guard = 0;
        nv = 0; ce = 0;
        while (nv < M && guard < 600) begin
            int completed;
            bit do_hold;
            @(negedge clk);
            completed = ce;
            do_hold = holds && (((guard % 7) == 3) || ((guard % 11) == 5));
            if (do_hold) begin
                mode = MODE_HOLD; act_valid = 0;
                junk_feed();
            end else begin
                mode = MODE_COMPUTE; ce++;
                if (tf < M) begin
                    act_valid = 1;
                    for (int r = 0; r < N; r++) act_feed_arr[r] = A[tf][r];
                    tf++;
                end else begin
                    act_valid = 0;
                    junk_feed();
                end
            end
            #1;
            check_no_x();
            sample(completed);
            guard++;
        end
        if (nv != M) begin errors++; $display("MISMATCH stream ended with nv=%0d exp=%0d", nv, M); end
    endtask

    initial begin
        for (int c = 0; c < N; c++) begin weight_feed_arr[c] = '0; act_feed_arr[c] = '0; end
        repeat (3) @(negedge clk);
        rst_n = 1;

        gen_w(1); gen_a(100);
        do_load();
        run_stream(0);

        hold_ticks(10);
        gen_a(200);
        run_stream(1);

        gen_w(777); gen_a(300);
        do_load();
        run_stream(1);

        $display("RESULT: checked=%0d errors=%0d", checked, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
