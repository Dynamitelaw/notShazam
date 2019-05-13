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
#include <stdlib.h>
#include <stdint.h>
#include "fft_accelerator.h"
#include <sys/ioctl.h>
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <unistd.h>
#include <arpa/inet.h>


int fft_accelerator_fd;

/* Read and print the position */
void print_spec() {
  fft_accelerator_arg_t vla;
  fft_accelerator_fft_t fft_struct;

  vla.fft_struct = &fft_struct;
  
  if (ioctl(fft_accelerator_fd, FFT_ACCELERATOR_READ_FFT, &vla)) {
      perror("ioctl(FFT_ACCELERATOR_READ_FFT) failed");
      return;
  }
  /*
  for (int p = 247; p < 255; p++){
    printf("(time: %u, address: %d, amplitude_raw: %d  0x%x, amplitude_ntohl: %d  0x%x) \n", fft_struct.time, p, fft_struct.points[p].ampl, fft_struct.points[p].ampl, ntohl(fft_struct.points[p].ampl), ntohl(fft_struct.points[p].ampl));
  }
  */
   
   int displayRows = 15;
   int newlines = 10;
   char displayArray [displayRows*128+newlines+55555];

   while (1) {
    //Zero out display array
    memset(displayArray, 0, 128*displayRows+newlines+1);

    if (ioctl(fft_accelerator_fd, FFT_ACCELERATOR_READ_FFT, &vla)) {
      perror("ioctl(FFT_ACCELERATOR_READ_FFT) failed");
      return;
    }
    
    for (int i=0; i<newlines; i++){
      strcat(displayArray, "\n");
    }
    
    double scaleFactor = 1000000000000000000;
    int scaledAmplitude;

    for (int r=0; r<displayRows; r++){
      scaleFactor = scaleFactor/15;
      for (int c=0; c<N_FREQUENCIES; c+=1){
        scaledAmplitude = abs(fft_struct.fft[c])/scaleFactor;
        if (scaledAmplitude > 0)
          strcat(displayArray, "|");
        else
          strcat(displayArray, " ");
      }
      strcat(displayArray, "\n");
    }

    strcat(displayArray, "\n");
    printf("%s", displayArray);
    usleep(350000);
  }

}


int get_samples(int n, fft_accelerator_fft_t *sample_array){
	fft_accelerator_arg_t vla;

	int c = 0;

	for (int i = 0; i < n; i++) {
		vla.fft_struct = sample_array + i;
		if (ioctl(fft_accelerator_fd, FFT_ACCELERATOR_READ_FFT, &vla)) {
			perror("ioctl(FFT_ACCELERATOR_READ_FFT) failed");
			return c;
		}
		c++;
	}
	return c;
}


void check_samples(int n, fft_accelerator_fft_t *sample_array) {
	int invalid_count = 0;
	int valid_times_count = 0;
	int missed = 0;
	int corrupt = 0;
	uint32_t time = sample_array[0].time;
	ampl_t fft[N_FREQUENCIES];
	uint8_t has_valid = sample_array[0].valid == 1;
	uint8_t is_good = has_valid;
	for (int i = 0; i < n; i++) {
		if (sample_array[0].valid != 0 && sample_array[0].valid != 1)
			printf("non legal \"valid\" value\n");
	}
	printf("valids are good \n");
	
	if (sample_array[0].valid == 1) {
		memcpy(fft, sample_array[0].fft, sizeof(fft));
	} else {
		invalid_count++;
	}
	for (int i = 1; i < n; i++) {
		if (sample_array[i].valid == 1) {
			if (sample_array[i].time == time) {
				if (has_valid == 0) {
					has_valid = 1;
					is_good  = 1;
					memcpy(fft, sample_array[i].fft, sizeof(fft));
				} else {
					for (int j = 0; j < N_FREQUENCIES; j++) {
						if (fft[j] != sample_array[0].fft[j]) {
							corrupt++;
							is_good = 0;
							break;
						}
					}
				}
			} else {
				missed += sample_array[i].time - (time + 1);
				valid_times_count += is_good;
				time = sample_array[i].time;
				has_valid = sample_array[0].valid;
				is_good = has_valid;
				if (sample_array[i].valid == 1) {
					memcpy(fft, sample_array[i].fft, sizeof(fft));
				}
			}
		} // NOT VALID -- continue;
		else {
			invalid_count++;
		}
	}

	//printf("invalid samples: %d\n", invalid_count);
	//printf("valid times: %d\n", valid_times_count);
	//printf("missed times: %d\n", missed);
	//printf("corrupt samples: %d\n", missed);

	for (int i=0; i<n; i++){
		printf("Time: %x\n", sample_array[i].time);
		printf("Valid: %x\n", sample_array[i].valid);
		for (int j=0; j<N_FREQUENCIES; j++) {
			printf("(%d:%x) ", j,sample_array[i].fft[j]);
		}
		printf("======================\n");
		
	}
}
				

int main()
{
  int i;
  static const char filename[] = "/dev/fft_accelerator";


  printf("FFT Accelerator Userspace program started\n");

  if ( (fft_accelerator_fd = open(filename, O_RDWR)) == -1) {
    fprintf(stderr, "could not open %s\n", filename);
    return -1;
  }
	
  print_spec();
  
  int n = 5;

  fft_accelerator_fft_t samples[n];
  int received = get_samples(n, samples);
  if (received != n) {
	  printf("could not get all samples. only got %d\n", received);
  }

  check_samples(received, samples);

  printf("FFT Accelerator Userspace program terminating\n");
  return 0;
}
