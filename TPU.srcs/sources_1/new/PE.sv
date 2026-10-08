`timescale 1ns / 1ps

package general_pkg;
    localparam int N     = 8;
    localparam int ACT_W = 8;
    localparam int ACC_W = 32;

    // mode[0] = load_en, mode[1] = compute_en. 2'b11 kullanilmaz -> HOLD gibi davranir.
    typedef enum logic [1:0] {
        MODE_HOLD    = 2'b00,
        MODE_LOAD    = 2'b01,
        MODE_COMPUTE = 2'b10
    } mode_t;

    typedef logic signed [ACT_W-1:0] act_t;
    typedef logic signed [ACC_W-1:0] acc_t;
endpackage

module PE
    import general_pkg::*;
(
    input  logic  clk,
    input  logic  rst_n,

    input  mode_t mode,

    input  act_t  act_in,
    input  act_t  weight_in,
    input  acc_t  psum_in,

    output act_t  act_out,
    output act_t  weight_out,
    output acc_t  psum_out
);

    act_t weight_reg;

    assign weight_out = weight_reg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            act_out    <= '0;
            weight_reg <= '0;
            psum_out   <= '0;
        end else begin
            case (mode)
                MODE_LOAD: begin
                    weight_reg <= weight_in;
                end
                MODE_COMPUTE: begin
                    act_out  <= act_in;
                    psum_out <= psum_in + act_in * weight_reg;
                end
                default: begin
                    // MODE_HOLD (ve kullanilmayan 2'b11): hicbir register degismez
                end
            endcase
        end
    end

endmodule
