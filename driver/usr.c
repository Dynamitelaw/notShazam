/*
 * Userspace program that communicates with the fft_accelerator device driver
 * through ioctls
 *
 * Eitan Kaplan
 *
 * Based on vga_ball.c by Stephen A. Edwards
 * Columbia University
 */

#include <stdio.h>
#include <stdint.h>
#include "fft_accelerator.h"
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>

#define R 2
#define RADIUS (R << 2)

int fft_accelerator_fd;

/* Read and print the position */
void print_peaks() {
  fft_accelerator_arg_t vla;
  fft_accelerator_peaks_t peaks;

  vla.peaks = &peaks;
  
  if (ioctl(fft_accelerator_fd, FFT_ACCELERATOR_READ_PEAKS, &vla)) {
      perror("ioctl(FFT_ACCELERATOR_READ_PEAKS) failed");
      return;
  }
  for (int p = 0; p < BINS; p++){
    printf("(time: %ud, frequency: %ud, amplitude: %d) \n", peaks.time, peaks.freq[p], peaks.ampl[p]);
  }
}


int main()
{
  fft_accelerator_arg_t vla;
  int i;
  static const char filename[] = "/dev/fft_accelerator";


  printf("FFT Accelerator Userspace program started\n");

  if ( (fft_accelerator_fd = open(filename, O_RDWR)) == -1) {
    fprintf(stderr, "could not open %s\n", filename);
    return -1;
  }

  printf("peaks: ");
  print_peaks();

  printf("VGA BALL Userspace program terminating\n");
  return 0;
}
