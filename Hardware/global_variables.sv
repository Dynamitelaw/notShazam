//`define RUNNING_SIMULATION  //define this to change ROM file locations to absolute paths fo vsim


// FFT Macros
`define NFFT 512 // if change this, change FREQ_WIDTH. Must be power of 2
`define nFFT 9  //log2(NFFT)

`define FREQS (`NFFT / 2)
`define FREQ_WIDTH 8 // if change NFFT, change this

`define FINAL_AMPL_WIDTH 32 // Must be less than or equal to INPUT_AMPL_WIDTH
`define INPUT_AMPL_WIDTH 32 
`define TIME_COUNTER_WIDTH 32

`define PEAKS 6 // Changing this requires many changes in code

`define SFFT_INPUT_WIDTH 24
`define SFFT_OUTPUT_WIDTH `INPUT_AMPL_WIDTH
`define SFFT_FIXEDPOINT_INPUTSCALING  //define this macro if you want to scale adc inputs to match FixedPoint magnitudes. Increases accuracy, but could lead to overflow
`define SFFT_FIXED_POINT_ACCURACY 7 
`define SFFT_STAGECOUNTER_WIDTH 5  //>= log2(nFFT)

//`define SFFT_DOWNSAMPLE_PRE  //define this macro if you want to downsample the incoming audio BEFORE the FFT calculation
`define SFFT_DOWNSAMPLE_PRE_FACTOR 2
`define nDOWNSAMPLE_PRE 1  // >= log2(SFFT_DOWNSAMPLE_PRE_FACTOR)

`define SFFT_DOWNSAMPLE_POST  //define this macro if you want to downsample the outgoing FFT calculation (will skip calculations)
`define SFFT_DOWNSAMPLE_POST_FACTOR 256
`define nDOWNSAMPLE_POST 8  // >= log2(SFFT_DOWNSAMPLE_POST_FACTOR)

// Audio Codec Macros
`define AUDIO_IN_GAIN 9'h010
`define AUDIO_OUT_GAIN 9'h061

`define SAMPLE_RATE_CNTRL 9'd0  //see page 44 of datasheet of more info: https://statics.cirrus.com/pubs/proDatasheet/WM8731_v4.9.pdf

/*
// BINS NFFT=16
`define BIN_1 1
`define BIN_2 3
`define BIN_3 5
`define BIN_4 8
`define BIN_5 12
`define BIN_6 15
*/

// BINS NFFT=128
`define BIN_1 1
`define BIN_2 2
`define BIN_3 7
`define BIN_4 12
`define BIN_5 18
`define BIN_6 58

/*
// BINS NFFT=256
`define BIN_1 1
`define BIN_2 4
`define BIN_3 13
`define BIN_4 24
`define BIN_5 37
`define BIN_6 116
*/
