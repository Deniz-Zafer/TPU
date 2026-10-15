`timescale 1ns / 1ps

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
