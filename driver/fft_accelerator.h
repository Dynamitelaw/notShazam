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


typedef struct {
	double ampl[BINS];
 	uint8_t freq[BINS];
	uint32_t time;
} fft_accelerator_peaks_t;
  

typedef struct {
  fft_accelerator_peaks_t *peaks;
} fft_accelerator_arg_t;

#define FFT_ACCELERATOR_MAGIC 'p'

/* ioctls and their arguments */
#define FFT_ACCELERATOR_READ_PEAKS  _IOR(FFT_ACCELERATOR_MAGIC, 2, fft_accelerator_arg_t *)

#endif
