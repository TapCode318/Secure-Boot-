module sha3_real_wrapper #(
    parameter MAX_WORDS = 16
) (
    input  wire        clk_i,
    input  wire        rst_i,
    input  wire        init_i,
    input  wire        start_i,
    input  wire        data_valid_i,
    input  wire [31:0] data_i,
    output reg         busy_o,
    output reg         done_o,
    output reg [511:0] digest_o
);
    localparam ST_IDLE = 2'd0;
    localparam ST_FEED = 2'd1;
    localparam ST_WAIT = 2'd2;

    reg [1:0]  state_q;
    reg [7:0]  word_count_q;
    reg [7:0]  feed_idx_q;
    reg [31:0] msg_words [0:MAX_WORDS-1];
    integer k;

    wire         core_reset_w;
    wire [31:0]  core_in_w;
    wire         core_in_ready_w;
    wire         core_is_last_w;
    wire [1:0]   core_byte_num_w;
    wire         core_buffer_full_w;
    wire [511:0] core_out_w;
    wire         core_out_ready_w;

    assign core_reset_w    = rst_i | init_i;
    assign core_in_ready_w = (state_q == ST_FEED);
    assign core_in_w       = (word_count_q == 8'd0) ? 32'd0 : msg_words[feed_idx_q];
    assign core_is_last_w  = (state_q == ST_FEED) &&
                             ((word_count_q == 8'd0) ? 1'b1 : (feed_idx_q == (word_count_q - 8'd1)));
    assign core_byte_num_w = (word_count_q == 8'd0) ? 2'd0 : 2'd3;

    keccak u_keccak (
        .clk        (clk_i),
        .reset      (core_reset_w),
        .in         (core_in_w),
        .in_ready   (core_in_ready_w),
        .is_last    (core_is_last_w),
        .byte_num   (core_byte_num_w),
        .buffer_full(core_buffer_full_w),
        .out        (core_out_w),
        .out_ready  (core_out_ready_w)
    );

    always @(posedge clk_i) begin
        if (rst_i) begin
            state_q      <= ST_IDLE;
            word_count_q <= 8'd0;
            feed_idx_q   <= 8'd0;
            busy_o       <= 1'b0;
            done_o       <= 1'b0;
            digest_o     <= 512'd0;
            for (k = 0; k < MAX_WORDS; k = k + 1)
                msg_words[k] <= 32'd0;
        end else begin
            if (init_i) begin
                state_q      <= ST_IDLE;
                word_count_q <= 8'd0;
                feed_idx_q   <= 8'd0;
                busy_o       <= 1'b0;
                done_o       <= 1'b0;
                digest_o     <= 512'd0;
                for (k = 0; k < MAX_WORDS; k = k + 1)
                    msg_words[k] <= 32'd0;
            end else begin
                if (data_valid_i && !busy_o) begin
                    if (word_count_q < MAX_WORDS) begin
                        msg_words[word_count_q] <= data_i;
                        word_count_q            <= word_count_q + 8'd1;
                    end
                end

                case (state_q)
                    ST_IDLE: begin
                        if (start_i && !busy_o) begin
                            state_q    <= ST_FEED;
                            feed_idx_q <= 8'd0;
                            busy_o     <= 1'b1;
                            done_o     <= 1'b0;
                        end
                    end

                    ST_FEED: begin
                        if (!core_buffer_full_w) begin
                            if ((word_count_q == 8'd0) || (feed_idx_q == (word_count_q - 8'd1))) begin
                                state_q <= ST_WAIT;
                            end else begin
                                feed_idx_q <= feed_idx_q + 8'd1;
                            end
                        end
                    end

                    ST_WAIT: begin
                        if (core_out_ready_w) begin
                            digest_o <= core_out_w;
                            busy_o   <= 1'b0;
                            done_o   <= 1'b1;
                            state_q  <= ST_IDLE;
                        end
                    end

                    default: begin
                        state_q <= ST_IDLE;
                    end
                endcase
            end
        end
    end
endmodule