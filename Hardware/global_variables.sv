// FFT Macros
`define NFFT 8 // if change this, change FREQ_WIDTH. Must be power of 2
`define FREQS (`NFFT / 2)
`define FREQ_WIDTH 4 // if change NFFT, change this

`define FINAL_AMPL_WIDTH 24
`define INPUT_AMPL_WIDTH 24

`define PEAKS 6 // Changing this requires many changes in code

`define SFFT_PIPELINE_WIDTH 128  // Must be power of 2
`define SFFT_PIPELINE_DEPTH 3  // Must be log2(NFFT)
`define SFFT_INPUT_WIDTH 24
`define SFFT_OUTPUT_WIDTH `INPUT_AMPL_WIDTH

// Audio Codec Macros
`define AUDIO_IN_GAIN 9'h014
`define AUDIO_OUT_GAIN 9'h061

// BINS
`define BIN_1 1
`define BIN_2 3
`define BIN_3 5
`define BIN_4 8
`define BIN_5 12
`define BIN_6 15
// BINS
// `define BIN_1 1
// `define BIN_2 4
// `define BIN_3 13
// `define BIN_4 24
// `define BIN_5 37
// `define BIN_6 116
