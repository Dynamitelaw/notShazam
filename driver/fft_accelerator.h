#ifndef _FFT_ACCELERATOR_H
#define _FFT_ACCELERATOR_H

#include <linux/ioctl.h>
#include <linux/types.h>

#define BINS 6
#define FREQ_WIDTH_BYTES 1
#define FREQ_WIDTH_BITS 1
#define AMPL_WIDTH_BYTES 4
#define AMPL_WIDTH_BITS 24
#define AMPL_FRACTIONAL_BITS 7
#define COUNTER_WIDTH_BYES 4
#define SAMPLING_FREQ 48000u
#define DOWN_SAMPLING_FACTOR 512
#define N_FREQUENCIES 256 

#define AMPLITUDES_SIZE (N_FREQUENCIES * AMPL_WIDTH_BYTES)


typedef int32_t ampl_t;

typedef struct {
	ampl_t fft[N_FREQUENCIES];
	uint32_t time; 
	uint8_t valid;
} fft_accelerator_fft_t;
  

typedef struct {
  fft_accelerator_fft_t *fft_struct;
} fft_accelerator_arg_t;

#define FFT_ACCELERATOR_MAGIC 'p'

/* ioctls and their arguments */
#define FFT_ACCELERATOR_READ_FFT  _IOR(FFT_ACCELERATOR_MAGIC, 2, fft_accelerator_arg_t *)

#endif
