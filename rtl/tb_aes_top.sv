`timescale 1ns/1ps
import aes_pkg::*;

module tb_aes_top;

    logic         clk;
    logic         rst_n;

    // Key interface
    logic [127:0] s_key_in;
    logic         s_key_expand;
    logic         key_ready;

    // IV interface
    logic [127:0] s_iv;
    logic         s_iv_load;

    // Input stream
    logic         s_valid;
    logic         s_ready;
    logic [127:0] s_data;
    mode_t        s_mode;
    dir_t         s_dir;
    logic [7:0]   s_tag;

    // Output stream
    logic         m_valid;
    logic         m_ready;
    logic [127:0] m_data;
    logic [7:0]   m_tag;
    logic         m_err;

    // DUT
    aes_top #(
        .KEY_BITS(128)
    ) dut (
        .clk          (clk),
        .rst_n        (rst_n),

        .s_key_in     (s_key_in),
        .s_key_expand (s_key_expand),
        .key_ready    (key_ready),

        .s_iv         (s_iv),
        .s_iv_load    (s_iv_load),

        .s_valid      (s_valid),
        .s_ready      (s_ready),
        .s_data       (s_data),
        .s_mode       (s_mode),
        .s_dir        (s_dir),
        .s_tag        (s_tag),

        .m_valid      (m_valid),
        .m_ready      (m_ready),
        .m_data       (m_data),
        .m_tag        (m_tag),
        .m_err        (m_err)
    );

    // Clock 10ns
    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        // Init
        rst_n         = 0;
        s_key_in      = 128'h000102030405060708090A0B0C0D0E0F;
        s_key_expand  = 0;
        s_iv          = 128'h0;
        s_iv_load     = 0;

        s_valid       = 0;
        s_data        = 128'h00112233445566778899AABBCCDDEEFF;
        s_mode        = ECB;
        s_dir         = ENCRYPT;
        s_tag         = 8'h55;

        m_ready       = 1;

        // Reset
        #20;
        rst_n = 1;

        // Load IV (không bắt buộc với ECB, nhưng cứ làm cho sạch)
        @(posedge clk);
        s_iv_load = 1;
        @(posedge clk);
        s_iv_load = 0;

        // Start key expansion
        @(posedge clk);
        s_key_expand = 1;
        @(posedge clk);
        s_key_expand = 0;

        // Wait until key schedule done
        wait(key_ready == 1);

        // Send one ECB encrypt block
        wait(s_ready == 1);
        @(posedge clk);
        s_valid = 1;
        @(posedge clk);
        s_valid = 0;

        // Wait output
        wait(m_valid == 1);
        $display("m_data = %h", m_data);
        $display("m_tag  = %h", m_tag);
        $display("m_err  = %b", m_err);

        if (m_data == 128'h69C4E0D86A7B0430D8CDB78070B4C55A)
            $display("PASS");
        else
            $display("FAIL");

        #50;
        $finish;
    end

endmodule
