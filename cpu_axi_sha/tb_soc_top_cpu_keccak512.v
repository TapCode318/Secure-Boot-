`timescale 1ns/1ps

module tb_soc_top_connect_view;
    reg clk;
    reg rst;
    reg intr;

    integer i;

    // ===== waveform-friendly debug regs =====
    reg [3:0]  tb_state;
    reg        init_pulse;
    reg        start_pulse;
    reg        fw_read_pulse;
    reg        sha_feed_pulse;
    reg        compare_ok;
    reg [31:0] fw_addr_dbg;
    reg [31:0] fw_data_dbg;
    reg [31:0] sha_data_dbg;
    reg [31:0] fw_read_count;
    reg [31:0] sha_feed_count;
    reg [255:0] digest_dbg;

    reg [31:0] fw_words  [0:15];
    reg [31:0] sha_words [0:15];

    // state encoding cho dễ nhìn trên waveform
    localparam ST_RESET    = 4'd0;
    localparam ST_BOOT     = 4'd1;
    localparam ST_SHA_INIT = 4'd2;
    localparam ST_FW_READ  = 4'd3;
    localparam ST_SHA_FEED = 4'd4;
    localparam ST_SHA_START= 4'd5;
    localparam ST_SHA_DONE = 4'd6;
    localparam ST_FINISH   = 4'd7;

    soc_top #(
        .BOOT_ROM_FILE("boot_rom.hex"),
        .BOOT_ROM_WORDS(1024),
        .FIRMWARE_ROM_FILE("firmware_rom.hex"),
        .FIRMWARE_ROM_WORDS(16),
        .BOOT_BASE_ADDR(32'h0000_0000),
        .FW_BASE_ADDR(32'h1000_0000),
        .SHA_BASE_ADDR(32'h4000_0000)
    ) dut (
        .clk_i (clk),
        .rst_i (rst),
        .intr_i(intr)
    );

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        intr = 1'b0;
        rst  = 1'b1;
        tb_state       = ST_RESET;
        init_pulse     = 1'b0;
        start_pulse    = 1'b0;
        fw_read_pulse  = 1'b0;
        sha_feed_pulse = 1'b0;
        compare_ok     = 1'b0;
        fw_addr_dbg    = 32'd0;
        fw_data_dbg    = 32'd0;
        sha_data_dbg   = 32'd0;
        fw_read_count  = 32'd0;
        sha_feed_count = 32'd0;
        digest_dbg     = 256'd0;
        for (i = 0; i < 16; i = i + 1) begin
            fw_words[i]  = 32'd0;
            sha_words[i] = 32'd0;
        end

        repeat (20) @(posedge clk);
        rst = 1'b0;
        tb_state = ST_BOOT;

        $display("\n===========================================================");
        $display(" CPU -> Firmware ROM -> SHA connection view");
        $display("===========================================================\n");
    end

    initial begin
        repeat (15000) @(posedge clk);
        $display("\n[TIMEOUT] Chua thay SHA done.");
        print_summary;
        $finish;
    end

    // clear pulse mỗi cycle
    always @(posedge clk) begin
        init_pulse     <= 1'b0;
        start_pulse    <= 1'b0;
        fw_read_pulse  <= 1'b0;
        sha_feed_pulse <= 1'b0;

        if (!rst)
            digest_dbg <= dut.sha_digest;
    end

    // bắt sự kiện bus và sideband
    always @(posedge clk) begin
        if (!rst) begin
            // SHA init
            if (dut.axi_d_awvalid && dut.axi_d_awready &&
                dut.axi_d_wvalid  && dut.axi_d_wready  &&
                dut.axi_d_awaddr  == 32'h4000_0000     &&
                dut.axi_d_wdata   == 32'h0000_0001) begin
                init_pulse <= 1'b1;
                tb_state   <= ST_SHA_INIT;
                $display("[%0t] SHA_INIT", $time);
            end

            // CPU đọc firmware ROM
            if (dut.axi_d_arvalid && dut.axi_d_arready &&
                dut.axi_d_araddr >= 32'h1000_0000 && dut.axi_d_araddr < 32'h1000_0040) begin
                fw_addr_dbg <= dut.axi_d_araddr;
            end

            if (dut.axi_d_rvalid && dut.axi_d_rready &&
                fw_addr_dbg >= 32'h1000_0000 && fw_addr_dbg < 32'h1000_0040) begin
                fw_read_pulse <= 1'b1;
                fw_data_dbg   <= dut.axi_d_rdata;
                tb_state      <= ST_FW_READ;
                if (fw_read_count < 16) begin
                    fw_words[fw_read_count] <= dut.axi_d_rdata;
                    $display("[%0t] FW_READ   FW[%0d] @%08x = %08x",
                             $time, fw_read_count, fw_addr_dbg, dut.axi_d_rdata);
                    fw_read_count <= fw_read_count + 1;
                end
            end

            // CPU ghi dữ liệu vào SHA
            if (dut.axi_d_awvalid && dut.axi_d_awready &&
                dut.axi_d_wvalid  && dut.axi_d_wready  &&
                dut.axi_d_awaddr  == 32'h4000_0008) begin
                sha_feed_pulse <= 1'b1;
                sha_data_dbg   <= dut.axi_d_wdata;
                tb_state       <= ST_SHA_FEED;
                if (sha_feed_count < 16) begin
                    sha_words[sha_feed_count] <= dut.axi_d_wdata;
                    $display("[%0t] SHA_FEED  IN[%0d]          = %08x",
                             $time, sha_feed_count, dut.axi_d_wdata);
                    sha_feed_count <= sha_feed_count + 1;
                end
            end

            // SHA start
            if (dut.axi_d_awvalid && dut.axi_d_awready &&
                dut.axi_d_wvalid  && dut.axi_d_wready  &&
                dut.axi_d_awaddr  == 32'h4000_0000     &&
                dut.axi_d_wdata   == 32'h0000_0002) begin
                start_pulse <= 1'b1;
                tb_state    <= ST_SHA_START;
                $display("[%0t] SHA_START", $time);
            end

            if (dut.sha_done) begin
                tb_state <= ST_SHA_DONE;
                compare_streams;
                print_summary;
                tb_state <= ST_FINISH;
                #20;
                $finish;
            end
        end
    end

    task compare_streams;
        integer k;
        integer mismatch;
        begin
            mismatch = 0;
            if (fw_read_count != sha_feed_count)
                mismatch = mismatch + 1;

            for (k = 0; k < fw_read_count && k < sha_feed_count; k = k + 1)
                if (fw_words[k] !== sha_words[k])
                    mismatch = mismatch + 1;

            compare_ok = (mismatch == 0);
            if (mismatch == 0)
                $display("\n[CHECK] PASS: CPU da doc firmware va dua dung vao SHA.");
            else
                $display("\n[CHECK] FAIL: luong CPU -> SHA khong khop.");
        end
    endtask

    task print_summary;
        integer k;
        begin
            $display("\n================ CONNECT SUMMARY ================");
            $display("fw_read_count  = %0d", fw_read_count);
            $display("sha_feed_count = %0d", sha_feed_count);
            $display("compare_ok     = %0d", compare_ok);
            $display("tb_state       = %0d", tb_state);
            $display("\nFirmware words:");
            for (k = 0; k < fw_read_count; k = k + 1)
                $display("  FW[%0d]      = %08x", k, fw_words[k]);
            $display("\nSHA input words:");
            for (k = 0; k < sha_feed_count; k = k + 1)
                $display("  SHA_IN[%0d]  = %08x", k, sha_words[k]);
            $display("\nDigest hien tai (theo soc_top dang expose):");
            $display("  %064x", digest_dbg);
            $display("=================================================\n");
        end
    endtask

endmodule
