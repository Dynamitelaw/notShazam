#ifndef _FFT_ACCELERATOR_H
#define _FFT_ACCELERATOR_H

#include <linux/ioctl.h>
#include <linux/types.h>

typedef struct {
	int32_t ampl[6];
 	uint8_t freq[6];
	uint32_t time;
} fft_accelerator_peaks_t;
  

typedef struct {
  fft_accelerator_peaks_t peaks;
} fft_accelerator_arg_t;

#define FFT_ACCELERATOR_MAGIC 'q'

/* ioctls and their arguments */
#define FFT_ACCELERATOR_READ_PEAKS  _IOR(FFT_ACCELERATOR_MAGIC, 2, fft_accelerator_arg_t *)

#endif
