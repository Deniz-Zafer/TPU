`timescale 1ns / 1ps

// Memory (Weight_Buffer + Act_Buffer + Result_Buffer) self-checking testbench:
//  - Weight: yaz, satir 7den 0a oku
//  - Act / Result ping-pong: bir banka okunurken diger bankaya yazma, swap sonrasi roller degisimi

module tb_memory;
    import general_pkg::*;

    logic clk = 0, rst_n = 0;
    always #5 clk = ~clk;

    int errors = 0, checked = 0;

    logic       w_we;
    logic [3:0] w_waddr, w_raddr;
    act_t       w_wdata [N], w_rdata [N];
    logic       a_swap, a_we, a_bank;
    logic [3:0] a_waddr, a_raddr;
    act_t       a_wdata [N], a_rdata [N];
    logic       r_swap, r_we, r_bank;
    logic [3:0] r_waddr, r_raddr;
    acc_t       r_wdata [N], r_rdata [N];

    Memory #(.W_DEPTH(16), .A_DEPTH(16), .R_DEPTH(16)) dut (
        .clk(clk), .rst_n(rst_n),
        .w_we(w_we), .w_waddr(w_waddr), .w_wdata(w_wdata), .w_raddr(w_raddr), .w_rdata(w_rdata),
        .a_swap(a_swap), .a_we(a_we), .a_waddr(a_waddr), .a_wdata(a_wdata), .a_raddr(a_raddr), .a_rdata(a_rdata), .a_compute_bank(a_bank),
        .r_swap(r_swap), .r_we(r_we), .r_waddr(r_waddr), .r_wdata(r_wdata), .r_raddr(r_raddr), .r_rdata(r_rdata), .r_write_bank(r_bank)
    );

    function automatic act_t wv(int i, int c);  return act_t'(i*10 + c - 40);           endfunction
    function automatic act_t a1(int t, int i);  return act_t'(t*8 + i - 60);            endfunction
    function automatic act_t a2(int t, int i);  return act_t'(100 - t*9 - i);           endfunction
    function automatic acc_t r1(int t, int c);  return acc_t'(t*100000 - c*777 - 500000); endfunction
    function automatic acc_t r2(int t, int c);  return acc_t'(-t*65537 + c*13 + 123456);  endfunction

    task automatic chk_act(input string tag, input int t, input bit second);
        for (int i = 0; i < N; i++) begin
            act_t exp = second ? a2(t, i) : a1(t, i);
            checked++;
            if (a_rdata[i] !== exp) begin
                errors++;
                if (errors < 12) $display("MISMATCH %s t=%0d i=%0d got=%0d exp=%0d", tag, t, i, a_rdata[i], exp);
            end
        end
    endtask

    initial begin
        w_we = 0; w_waddr = 0; w_raddr = 0; a_swap = 0; a_we = 0; a_waddr = 0; a_raddr = 0;
        r_swap = 0; r_we = 0; r_waddr = 0; r_raddr = 0;
        for (int i = 0; i < N; i++) begin w_wdata[i] = 0; a_wdata[i] = 0; r_wdata[i] = 0; end
        repeat (3) @(negedge clk);
        rst_n = 1;
        @(negedge clk);

        // ===== 1) Weight_Buffer: 8 satir yaz, satir 7'den 0'a oku =====
        for (int row = 0; row < 8; row++) begin
            w_we = 1; w_waddr = row;
            for (int c = 0; c < N; c++) w_wdata[c] = wv(row, c);
            @(negedge clk);
        end
        w_we = 0;
        for (int k = 0; k < 8; k++) begin
            int row = 7 - k;
            w_raddr = row;
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (w_rdata[c] !== wv(row, c)) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH WEIGHT row=%0d c=%0d got=%0d exp=%0d", row, c, w_rdata[c], wv(row, c));
                end
            end
            @(negedge clk);
        end

        // ===== 2) Act_Buffer ping-pong =====
        // sel=0 -> compute bankasi 0, fill bankasi 1. A1'i fill bankasina yaz.
        for (int t = 0; t < 10; t++) begin
            a_we = 1; a_waddr = t;
            for (int i = 0; i < N; i++) a_wdata[i] = a1(t, i);
            @(negedge clk);
        end
        a_we = 0;
        a_swap = 1; @(negedge clk); a_swap = 0;
        if (a_bank !== 1'b1) begin errors++; $display("MISMATCH act compute_bank after swap"); end

        // A1'i compute bankasindan oku, AYNI ANDA yeni fill bankasina A2 yaz
        for (int t = 0; t < 10; t++) begin
            a_raddr = t;
            a_we = 1; a_waddr = t;
            for (int i = 0; i < N; i++) a_wdata[i] = a2(t, i);
            @(posedge clk); #1;
            chk_act("ACT_A1_while_writing_A2", t, 0);
            @(negedge clk);
        end
        a_we = 0;
        a_swap = 1; @(negedge clk); a_swap = 0;
        for (int t = 0; t < 10; t++) begin
            a_raddr = t;
            @(posedge clk); #1;
            chk_act("ACT_A2", t, 1);
            @(negedge clk);
        end

        // ===== 3) Result_Buffer ping-pong =====
        // sel=0 -> dizi bank 0'a yazar. R1 yaz.
        for (int t = 0; t < 10; t++) begin
            r_we = 1; r_waddr = t;
            for (int c = 0; c < N; c++) r_wdata[c] = r1(t, c);
            @(negedge clk);
        end
        r_we = 0;
        r_swap = 1; @(negedge clk); r_swap = 0;
        // host R1'i okur, AYNI ANDA dizi yeni yazma bankasina R2 yazar
        for (int t = 0; t < 10; t++) begin
            r_raddr = t;
            r_we = 1; r_waddr = t;
            for (int c = 0; c < N; c++) r_wdata[c] = r2(t, c);
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (r_rdata[c] !== r1(t, c)) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH RES_R1 t=%0d c=%0d got=%0d exp=%0d", t, c, r_rdata[c], r1(t, c));
                end
            end
            @(negedge clk);
        end
        r_we = 0;
        r_swap = 1; @(negedge clk); r_swap = 0;
        for (int t = 0; t < 10; t++) begin
            r_raddr = t;
            @(posedge clk); #1;
            for (int c = 0; c < N; c++) begin
                checked++;
                if (r_rdata[c] !== r2(t, c)) begin
                    errors++;
                    if (errors < 12) $display("MISMATCH RES_R2 t=%0d c=%0d got=%0d exp=%0d", t, c, r_rdata[c], r2(t, c));
                end
            end
            @(negedge clk);
        end

        $display("RESULT: checked=%0d errors=%0d", checked, errors);
        if (errors == 0) $display("PASS"); else $display("FAIL");
        $finish;
    end
endmodule
