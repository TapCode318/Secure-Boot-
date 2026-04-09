`timescale 1ns/1ps

module tb_soc_top_cpu_to_sha;

    reg clk;
    reg rst;
    reg intr;

    integer i;
    integer error_count;

    // ===== chỉnh chỗ này nếu số word input SHA thay đổi =====
    localparam integer EXPECT_SHA_WORDS = 4;
    localparam integer MAX_WORDS        = 64;

    // ===== log dữ liệu CPU đọc từ firmware ROM (debug only) =====
    integer fw_dbg_read_count;
    reg [31:0] fw_dbg_words [0:MAX_WORDS-1];

    // ===== dữ liệu thực tế CPU đã đưa vào SHA =====
    integer sha_feed_count;
    reg [31:0] sha_words [0:MAX_WORDS-1];

    // ===== dữ liệu kỳ vọng lấy từ file firmware_rom.hex =====
    reg [31:0] exp_fw_words [0:15];

    // ===== trạng thái monitor =====
    reg init_seen;
    reg start_seen;
    reg done_seen;

    // ===== tracker cho AXI read firmware (debug only) =====
    reg        fw_rd_active;
    reg [31:0] fw_rd_addr;
    reg [7:0]  fw_rd_beats_left;

    soc_top #(
        .BOOT_ROM_FILE("boot_rom.hex"),
        .BOOT_ROM_WORDS(1024),
        .FIRMWARE_ROM_FILE("firmware_rom.hex"),
        .FIRMWARE_ROM_WORDS(16),
        .BOOT_BASE_ADDR(32'h0000_0000),
        .FW_BASE_ADDR  (32'h1000_0000),
        .SHA_BASE_ADDR (32'h4000_0000)
    ) dut (
        .clk_i (clk),
        .rst_i (rst),
        .intr_i(intr)
    );

    // =========================================================
    // CLOCK
    // =========================================================
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // =========================================================
    // INIT
    // =========================================================
    initial begin
        intr = 1'b0;
        rst  = 1'b1;

        error_count      = 0;
        fw_dbg_read_count = 0;
        sha_feed_count   = 0;

        init_seen        = 1'b0;
        start_seen       = 1'b0;
        done_seen        = 1'b0;

        fw_rd_active     = 1'b0;
        fw_rd_addr       = 32'd0;
        fw_rd_beats_left = 8'd0;

        for (i = 0; i < MAX_WORDS; i = i + 1) begin
            fw_dbg_words[i] = 32'd0;
            sha_words[i]    = 32'd0;
        end

        for (i = 0; i < 16; i = i + 1)
            exp_fw_words[i] = 32'h0000_0013;

        // đọc firmware kỳ vọng trực tiếp từ file
        $readmemh("firmware_rom.hex", exp_fw_words);

        repeat (20) @(posedge clk);
        rst = 1'b0;

        $display("\n===============================================================");
        $display(" TEST: CPU boot -> read firmware ROM -> transfer firmware to SHA");
        $display("===============================================================\n");
    end

    // =========================================================
    // TIMEOUT
    // =========================================================
    initial begin
        repeat (12000) @(posedge clk);
        $display("\n[TIMEOUT] Khong thay SHA done.");
        compare_expected_vs_sha;
        show_report;
        $finish;
    end

    // =========================================================
    // DEBUG monitor: CPU đọc firmware ROM qua AXI
    // Chỉ để quan sát, KHÔNG dùng làm tiêu chí PASS/FAIL
    // =========================================================
    always @(posedge clk) begin
        if (rst) begin
            fw_rd_active     <= 1'b0;
            fw_rd_addr       <= 32'd0;
            fw_rd_beats_left <= 8'd0;
        end else begin
            // bắt đầu 1 transaction đọc vùng firmware
            if (dut.axi_d_arvalid && dut.axi_d_arready &&
                (dut.axi_d_araddr >= 32'h1000_0000) &&
                (dut.axi_d_araddr <  32'h1000_0040)) begin
                fw_rd_active     <= 1'b1;
                fw_rd_addr       <= dut.axi_d_araddr;
                fw_rd_beats_left <= dut.axi_d_arlen + 8'd1;
            end

            // từng beat trả dữ liệu
            if (fw_rd_active && dut.axi_d_rvalid && dut.axi_d_rready) begin
                if (fw_dbg_read_count < MAX_WORDS) begin
                    fw_dbg_words[fw_dbg_read_count] <= dut.axi_d_rdata;
                    $display("[%0t] CPU doc firmware  FW_DBG[%0d] @%08x = %08x",
                             $time, fw_dbg_read_count, fw_rd_addr, dut.axi_d_rdata);
                    fw_dbg_read_count <= fw_dbg_read_count + 1;
                end

                fw_rd_addr <= fw_rd_addr + 32'd4;

                if ((fw_rd_beats_left == 8'd1) || dut.axi_d_rlast) begin
                    fw_rd_active     <= 1'b0;
                    fw_rd_beats_left <= 8'd0;
                end else begin
                    fw_rd_beats_left <= fw_rd_beats_left - 8'd1;
                end
            end
        end
    end

    // =========================================================
    // Monitor đúng cho SHA: bắt tín hiệu nội bộ sau MMIO
    // =========================================================
    always @(posedge clk) begin
        if (!rst) begin
            if (dut.sha_init) begin
                init_seen <= 1'b1;
                $display("[%0t] CPU -> SHA CTRL : INIT", $time);
            end

            if (dut.sha_data_valid) begin
                if (sha_feed_count < MAX_WORDS) begin
                    sha_words[sha_feed_count] <= dut.sha_data;
                    $display("[%0t] CPU -> SHA DATA  IN[%0d] = %08x",
                             $time, sha_feed_count, dut.sha_data);
                    sha_feed_count <= sha_feed_count + 1;
                end
            end

            if (dut.sha_start) begin
                start_seen <= 1'b1;
                $display("[%0t] CPU -> SHA CTRL : START", $time);
            end

            if (dut.sha_done && !done_seen) begin
                done_seen <= 1'b1;
                $display("[%0t] SHA done", $time);
                #1;
                compare_expected_vs_sha;
                show_report;
                $finish;
            end
        end
    end

    // =========================================================
    // CHECK: chỉ so dữ liệu đưa vào SHA với dữ liệu kỳ vọng
    // =========================================================
    task compare_expected_vs_sha;
        integer k;
        begin
            error_count = 0;

            if (!init_seen) begin
                error_count = error_count + 1;
                $display("[CHECK] FAIL: khong thay xung sha_init.");
            end

            if (!start_seen) begin
                error_count = error_count + 1;
                $display("[CHECK] FAIL: khong thay xung sha_start.");
            end

            if (!done_seen && !dut.sha_done) begin
                error_count = error_count + 1;
                $display("[CHECK] FAIL: khong thay sha_done.");
            end

            if (sha_feed_count !== EXPECT_SHA_WORDS) begin
                error_count = error_count + 1;
                $display("[CHECK] FAIL: so word dua vao SHA = %0d, ky vong = %0d",
                         sha_feed_count, EXPECT_SHA_WORDS);
            end

            for (k = 0; k < EXPECT_SHA_WORDS && k < sha_feed_count; k = k + 1) begin
                if (sha_words[k] !== exp_fw_words[k]) begin
                    error_count = error_count + 1;
                    $display("[CHECK] FAIL: word %0d khong khop, EXP=%08x SHA=%08x",
                             k, exp_fw_words[k], sha_words[k]);
                end
            end

            if (error_count == 0)
                $display("[CHECK] PASS: CPU da dua dung %0d word firmware vao SHA.",
                         EXPECT_SHA_WORDS);

            if (fw_dbg_read_count > EXPECT_SHA_WORDS) begin
                $display("[NOTE] CPU doc firmware qua bus nhieu hon %0d word la binh thuong do cache/prefetch.",
                         EXPECT_SHA_WORDS);
            end
        end
    endtask

    // =========================================================
    // REPORT
    // =========================================================
    task show_report;
        integer j;
        begin
            $display("\n==================== CPU -> SHA REPORT ====================");
            $display("INIT seen        : %0d", init_seen);
            $display("START seen       : %0d", start_seen);
            $display("DONE seen        : %0d", done_seen);
            $display("FW debug reads   : %0d", fw_dbg_read_count);
            $display("SHA words        : %0d", sha_feed_count);

            $display("\nExpected firmware words (tu file firmware_rom.hex):");
            for (j = 0; j < EXPECT_SHA_WORDS; j = j + 1)
                $display("  EXP[%0d]      = %08x", j, exp_fw_words[j]);

            $display("\nWords CPU da dua vao SHA:");
            for (j = 0; j < sha_feed_count; j = j + 1)
                $display("  SHA_IN[%0d]   = %08x", j, sha_words[j]);

            $display("\nFirmware debug stream tren AXI (co the nhieu hon do cache/prefetch):");
            for (j = 0; j < fw_dbg_read_count; j = j + 1)
                $write("%08x ", fw_dbg_words[j]);
            $display("");

            $display("\nExpected SHA input stream:");
            for (j = 0; j < EXPECT_SHA_WORDS; j = j + 1)
                $write("%08x ", exp_fw_words[j]);
            $display("");

            $display("\nActual SHA input stream:");
            for (j = 0; j < sha_feed_count; j = j + 1)
                $write("%08x ", sha_words[j]);
            $display("");

            $display("\nSHA digest hien tai:");
            $display("  %0128x", dut.sha_digest);
            $display("===========================================================\n");
        end
    endtask

endmodule