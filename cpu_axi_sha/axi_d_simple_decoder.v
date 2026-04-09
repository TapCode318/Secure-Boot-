module axi_d_simple_decoder #(
    parameter ROM_BASE_ADDR = 32'h1000_0000,
    parameter ROM_HIGH_ADDR = 32'h1000_FFFF,
    parameter ROM_INIT_FILE = "D:/riscv-master/firmware_rom.hex",
    parameter SHA_BASE_ADDR = 32'h4000_0000,
    parameter SHA_HIGH_ADDR = 32'h4000_00FF
)
(
    input  wire        clk_i,
    input  wire        rst_i,

    input  wire        m_awvalid_i,
    input  wire [31:0] m_awaddr_i,
    input  wire [3:0]  m_awid_i,
    input  wire [7:0]  m_awlen_i,
    input  wire [1:0]  m_awburst_i,
    input  wire        m_wvalid_i,
    input  wire [31:0] m_wdata_i,
    input  wire [3:0]  m_wstrb_i,
    input  wire        m_wlast_i,
    input  wire        m_bready_i,
    input  wire        m_arvalid_i,
    input  wire [31:0] m_araddr_i,
    input  wire [3:0]  m_arid_i,
    input  wire [7:0]  m_arlen_i,
    input  wire [1:0]  m_arburst_i,
    input  wire        m_rready_i,

    output wire        m_awready_o,
    output wire        m_wready_o,
    output wire        m_bvalid_o,
    output wire [1:0]  m_bresp_o,
    output wire [3:0]  m_bid_o,
    output wire        m_arready_o,
    output wire        m_rvalid_o,
    output wire [31:0] m_rdata_o,
    output wire [1:0]  m_rresp_o,
    output wire [3:0]  m_rid_o,
    output wire        m_rlast_o,

    output wire        sha_init_o,
    output wire        sha_start_o,
    output wire        sha_data_valid_o,
    output wire [31:0] sha_data_o,
    input  wire        sha_busy_i,
    input  wire        sha_done_i,
    input  wire [511:0] sha_digest_i
);

    wire aw_to_rom_w = (m_awaddr_i >= ROM_BASE_ADDR) && (m_awaddr_i <= ROM_HIGH_ADDR);
    wire aw_to_sha_w = (m_awaddr_i >= SHA_BASE_ADDR) && (m_awaddr_i <= SHA_HIGH_ADDR);
    wire ar_to_rom_w = (m_araddr_i >= ROM_BASE_ADDR) && (m_araddr_i <= ROM_HIGH_ADDR);
    wire ar_to_sha_w = (m_araddr_i >= SHA_BASE_ADDR) && (m_araddr_i <= SHA_HIGH_ADDR);

    reg wr_sel_sha_q;
    reg wr_sel_rom_q;
    reg rd_sel_sha_q;
    reg rd_sel_rom_q;

    // ROM slave wires
    wire        rom_awready_w;
    wire        rom_wready_w;
    wire        rom_bvalid_w;
    wire [1:0]  rom_bresp_w;
    wire [3:0]  rom_bid_w;
    wire        rom_arready_w;
    wire        rom_rvalid_w;
    wire [31:0] rom_rdata_w;
    wire [1:0]  rom_rresp_w;
    wire [3:0]  rom_rid_w;
    wire        rom_rlast_w;

    // SHA slave wires
    wire        sha_awready_w;
    wire        sha_wready_w;
    wire        sha_bvalid_w;
    wire [1:0]  sha_bresp_w;
    wire [3:0]  sha_bid_w;
    wire        sha_arready_w;
    wire        sha_rvalid_w;
    wire [31:0] sha_rdata_w;
    wire [1:0]  sha_rresp_w;
    wire [3:0]  sha_rid_w;
    wire        sha_rlast_w;

    always @(posedge clk_i) begin
        if (rst_i) begin
            wr_sel_sha_q <= 1'b0;
            wr_sel_rom_q <= 1'b0;
            rd_sel_sha_q <= 1'b0;
            rd_sel_rom_q <= 1'b0;
        end else begin
            if (m_awvalid_i && m_awready_o) begin
                wr_sel_sha_q <= aw_to_sha_w;
                wr_sel_rom_q <= aw_to_rom_w;
            end
            if (m_bvalid_o && m_bready_i) begin
                wr_sel_sha_q <= 1'b0;
                wr_sel_rom_q <= 1'b0;
            end

            if (m_arvalid_i && m_arready_o) begin
                rd_sel_sha_q <= ar_to_sha_w;
                rd_sel_rom_q <= ar_to_rom_w;
            end
            if (m_rvalid_o && m_rready_i && m_rlast_o) begin
                rd_sel_sha_q <= 1'b0;
                rd_sel_rom_q <= 1'b0;
            end
        end
    end

    axi_simple_rom #(
        .BASE_ADDR(ROM_BASE_ADDR),
        .MEM_WORDS(((ROM_HIGH_ADDR - ROM_BASE_ADDR + 1) >> 2)),
        .INIT_FILE(ROM_INIT_FILE)
    ) u_firmware_rom (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .axi_awvalid_i(m_awvalid_i && aw_to_rom_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_awid_i   (m_awid_i),
        .axi_awlen_i  (m_awlen_i),
        .axi_awburst_i(m_awburst_i),
        .axi_wvalid_i (m_wvalid_i && wr_sel_rom_q),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_wlast_i  (m_wlast_i),
        .axi_bready_i (m_bready_i && wr_sel_rom_q),
        .axi_arvalid_i(m_arvalid_i && ar_to_rom_w),
        .axi_araddr_i (m_araddr_i),
        .axi_arid_i   (m_arid_i),
        .axi_arlen_i  (m_arlen_i),
        .axi_arburst_i(m_arburst_i),
        .axi_rready_i (m_rready_i && rd_sel_rom_q),
        .axi_awready_o(rom_awready_w),
        .axi_wready_o (rom_wready_w),
        .axi_bvalid_o (rom_bvalid_w),
        .axi_bresp_o  (rom_bresp_w),
        .axi_bid_o    (rom_bid_w),
        .axi_arready_o(rom_arready_w),
        .axi_rvalid_o (rom_rvalid_w),
        .axi_rdata_o  (rom_rdata_w),
        .axi_rresp_o  (rom_rresp_w),
        .axi_rid_o    (rom_rid_w),
        .axi_rlast_o  (rom_rlast_w)
    );

    axi_sha3_regs #(
        .BASE_ADDR(SHA_BASE_ADDR)
    ) u_sha_regs (
        .clk_i(clk_i),
        .rst_i(rst_i),
        .axi_awvalid_i(m_awvalid_i && aw_to_sha_w),
        .axi_awaddr_i (m_awaddr_i),
        .axi_awid_i   (m_awid_i),
        .axi_awlen_i  (m_awlen_i),
        .axi_awburst_i(m_awburst_i),
        .axi_wvalid_i (m_wvalid_i && wr_sel_sha_q),
        .axi_wdata_i  (m_wdata_i),
        .axi_wstrb_i  (m_wstrb_i),
        .axi_wlast_i  (m_wlast_i),
        .axi_bready_i (m_bready_i && wr_sel_sha_q),
        .axi_arvalid_i(m_arvalid_i && ar_to_sha_w),
        .axi_araddr_i (m_araddr_i),
        .axi_arid_i   (m_arid_i),
        .axi_arlen_i  (m_arlen_i),
        .axi_arburst_i(m_arburst_i),
        .axi_rready_i (m_rready_i && rd_sel_sha_q),
        .axi_awready_o(sha_awready_w),
        .axi_wready_o (sha_wready_w),
        .axi_bvalid_o (sha_bvalid_w),
        .axi_bresp_o  (sha_bresp_w),
        .axi_bid_o    (sha_bid_w),
        .axi_arready_o(sha_arready_w),
        .axi_rvalid_o (sha_rvalid_w),
        .axi_rdata_o  (sha_rdata_w),
        .axi_rresp_o  (sha_rresp_w),
        .axi_rid_o    (sha_rid_w),
        .axi_rlast_o  (sha_rlast_w),
        .sha_init_o   (sha_init_o),
        .sha_start_o  (sha_start_o),
        .sha_data_valid_o(sha_data_valid_o),
        .sha_data_o   (sha_data_o),
        .sha_busy_i   (sha_busy_i),
        .sha_done_i   (sha_done_i),
        .sha_digest_i (sha_digest_i)
    );

assign m_awready_o = aw_to_rom_w ? rom_awready_w :
                     aw_to_sha_w ? sha_awready_w : 1'b0;

assign m_wready_o  = wr_sel_rom_q ? rom_wready_w :
                     wr_sel_sha_q ? sha_wready_w : 1'b0;

assign m_bvalid_o  = wr_sel_rom_q ? rom_bvalid_w :
                     wr_sel_sha_q ? sha_bvalid_w : 1'b0;

assign m_bresp_o   = wr_sel_rom_q ? rom_bresp_w :
                     wr_sel_sha_q ? sha_bresp_w : 2'b00;

assign m_bid_o     = wr_sel_rom_q ? rom_bid_w :
                     wr_sel_sha_q ? sha_bid_w : 4'd0;

assign m_arready_o = ar_to_rom_w ? rom_arready_w :
                     ar_to_sha_w ? sha_arready_w : 1'b0;

assign m_rvalid_o  = rd_sel_rom_q ? rom_rvalid_w :
                     rd_sel_sha_q ? sha_rvalid_w : 1'b0;

assign m_rdata_o   = rd_sel_rom_q ? rom_rdata_w :
                     rd_sel_sha_q ? sha_rdata_w : 32'h0000_0000;

assign m_rresp_o   = rd_sel_rom_q ? rom_rresp_w :
                     rd_sel_sha_q ? sha_rresp_w : 2'b00;

assign m_rid_o     = rd_sel_rom_q ? rom_rid_w :
                     rd_sel_sha_q ? sha_rid_w : 4'd0;

assign m_rlast_o   = rd_sel_rom_q ? rom_rlast_w :
                     rd_sel_sha_q ? sha_rlast_w : 1'b0;
endmodule
