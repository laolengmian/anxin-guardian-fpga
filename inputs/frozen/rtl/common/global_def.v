// Global definitions for 720p RGB565 4-Bank architecture
// Migrated from Michu 480p RGB888 to our 720p RGB565
// Date: 2026-09-18

// ============================================================================
// Clock Frequencies
// ============================================================================
`define CLK_REF_HZ          100_000_000  // 100 MHz reference clock (crystal)
`define CLK_MEM_HZ          125_000_000  // 125 MHz SDRAM clock (official sdr_as_ram operating point, sys_pll C1; C2 = 125MHz@180deg = mem_clk_sft)
`define CLK_VIDEO_HZ        75_000_000   // 75 MHz video clock (720p@60.606Hz, actual 74.25MHz)
`define CLK_SYSTEM_HZ       100_000_000  // 100 MHz system clock
`define CLK_AUDIO_HZ        12_288_000   // 12.288 MHz audio clock (48kHz × 256)

// ============================================================================
// Video Timing Parameters (720p@60.606Hz)
// ============================================================================
`define H_ACTIVE            1280
`define H_FP                110
`define H_SYNC              40
`define H_BP                220
`define H_TOTAL             1650         // 1280 + 110 + 40 + 220

`define V_ACTIVE            720
`define V_FP                5
`define V_SYNC              5
`define V_BP                20
`define V_TOTAL             750          // 720 + 5 + 5 + 20

// Frame rate: 1650 × 750 × 60 = 74.25 MHz (PLL outputs 75MHz, error <1%)

// ============================================================================
// Pixel Format (RGB565)
// ============================================================================
`define PIXEL_BITS          16           // RGB565: 5-6-5 bits
`define PIXELS_PER_WORD     2            // 32-bit word = 2 RGB565 pixels
`define WORD_BITS           32           // SDRAM word width

// ============================================================================
// Frame Buffer Layout (4-Bank Architecture)
// ============================================================================
// Each bank: 1280×720 pixels ÷ 2 pixels/word = 460,800 words = 1.8 MB
`define BANK_SIZE_WORDS     460800       // Words per bank
`define BANK_SIZE_BYTES     1843200      // Bytes per bank (460800 × 4)

// Bank base addresses (word-addressed)
`define BANK0_BASE          32'h00000000 // Bank 0: 0
`define BANK1_BASE          32'h00070800 // Bank 1: 460,800 words = 0x70800
`define BANK2_BASE          32'h000E1000 // Bank 2: 921,600 words = 0xE1000
`define BANK3_BASE          32'h00151800 // Bank 3: 1,382,400 words = 0x151800

// Total SDRAM usage: 4 × 460,800 = 1,843,200 words = 7.2 MB < 8MB SDRAM ✓

// ============================================================================
// Line and Burst Parameters
// ============================================================================
`define LINE_WIDTH_PIXELS   1280
`define LINE_WIDTH_WORDS    640          // 1280 pixels ÷ 2 pixels/word
`define BURST_SIZE          64           // Official SDRAM IP burst size
`define BURSTS_PER_LINE     10           // 640 words ÷ 64 words/burst

// ============================================================================
// FIFO Depths
// ============================================================================
`define READER_FIFO_DEPTH   1280         // 2 lines for ping-pong prefetch
`define LOADER_FIFO_DEPTH   512          // Loader input FIFO

// ============================================================================
// SDRAM Parameters (HX4S20C: 2M×32bit)
// ============================================================================
`define DATA_WIDTH          32
`define ADDR_WIDTH          21
`define DM_WIDTH            4
`define ROW_WIDTH           11
`define BA_WIDTH            2

// SDRAM timing calculations — 官方工作点125MHz（sdr_as_ram刷新计数按此校准，勿改）
`define SDR_CLK_PERIOD         (1000000000/125000000)  // 8 ns @ 125MHz; parentheses required for nested macro expansion
`define SELF_REFRESH_INTERVAL  (64000000/(`SDR_CLK_PERIOD)/(1<<(`ROW_WIDTH)))

// ============================================================================
// Debug and Diagnostic
// ============================================================================
`define ENABLE_SEG7_DISPLAY 1            // Enable 7-segment display
`define ENABLE_UNDERFLOW_STICKY 1        // Enable underflow detection

// ============================================================================
// RGB Conversion Macros
// ============================================================================

// RGB888 to RGB565 conversion
`define RGB888_TO_RGB565(rgb888) \
    {rgb888[23:19], rgb888[15:10], rgb888[7:3]}

// RGB565 to RGB888 expansion (for HDMI output)
`define RGB565_TO_RGB888(rgb565) \
    {rgb565[15:11], 3'b0, rgb565[10:5], 2'b0, rgb565[4:0], 3'b0}

// ============================================================================
// Bank State Encoding
// ============================================================================
`define BANK_STATE_IDLE     2'b00
`define BANK_STATE_LOADING  2'b01
`define BANK_STATE_READY    2'b10
`define BANK_STATE_DISPLAY  2'b11

// ============================================================================
// Error Codes (aligned with M6Preflight)
// ============================================================================
`define ERR_NONE            8'h00
`define ERR_SD_INIT_BASE    8'h01        // 0x01-0x0F: SD initialization
`define ERR_FAT32_BASE      8'h10        // 0x10-0x1F: FAT32 scanning
`define ERR_BMP_DECODE_BASE 8'h20        // 0x20-0x2F: BMP decoding
`define ERR_SDRAM_LOAD_BASE 8'h30        // 0x30-0x3F: SDRAM loading

// ============================================================================
// End of global_def.v
// ============================================================================
