// FFT Macros
`define NFFT 128 // if change this, change FREQ_WIDTH. Must be power of 2
`define nFFT 7  //log2(NFFT)

`define FREQS (`NFFT / 2)
`define FREQ_WIDTH 8 // if change NFFT, change this

`define FINAL_AMPL_WIDTH 24 // Must be less than or equal to INPUT_AMPL_WIDTH
`define INPUT_AMPL_WIDTH 24 
`define TIME_COUNTER_WIDTH 32

`define PEAKS 6 // Changing this requires many changes in code

`define SFFT_INPUT_WIDTH 24
`define SFFT_OUTPUT_WIDTH `INPUT_AMPL_WIDTH
`define SFFT_FIXED_POINT_ACCURACY 7
`define SFFT_STAGECOUNTER_WIDTH 3  //>= log2(nFFT)

// Audio Codec Macros
`define AUDIO_IN_GAIN 9'h014
`define AUDIO_OUT_GAIN 9'h061

// BINS NFFT=16
//`define BIN_1 1
//`define BIN_2 3
//`define BIN_3 5
//`define BIN_4 8
//`define BIN_5 12
//`define BIN_6 15

// BINS NFFT=128
`define BIN_1 1
`define BIN_2 2
`define BIN_3 7
`define BIN_4 12
`define BIN_5 18
`define BIN_6 58

// BINS NFFT=256
//`define BIN_1 1
//`define BIN_2 4
//`define BIN_3 13
//`define BIN_4 24
//`define BIN_5 37
//`define BIN_6 116
