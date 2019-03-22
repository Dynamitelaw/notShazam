
#import the pyplot and wavfile modules 

import matplotlib.pyplot as plt

from scipy.io import wavfile
from scipy import signal
import numpy as np
 


def generateConstellationMap(audioFilePath, fftResolution=512):
	'''
	Generates a constellation map for a given audio file.
	Method based on this article: http://coding-geek.com/how-shazam-works/

	Parameters:
		<string> audioFilePath: path to the input audio file. File must be a mono wave file with no metadata
		<int> fftResolution: number of frequencies to sample over (power of 2). Defaults to 512

	Returns:
		(times, peakFreaquencies)
			times: ndarray
				Array of time segments 
			peakFrequencies: ndarray
				Array of peak frequencies (in Hz)
	'''

	# Read the wav file (mono)
	samplingFrequency, signalData = wavfile.read(audioFilePath)

	#Generate spectogram
	frequencies, times, spectrogramData = signal.spectrogram(signalData, samplingFrequency, nperseg=fftResolution)
	spectrogramData = np.transpose(spectrogramData)  #transpose data, so each row is a single sample

	#Find the peak frequencies in the spectogram
	peakFrequencies = []
	for sample in spectrogramData:
		#Bin frequencies in logarithmic bands
		numberOfBins = 6

		#Find the index of the peak frequency in this sample
		peak = sample[0]
		peakIndex = 0

		for index in range(1, len(sample), 1):
			currentAmplitude = sample[index]
			if (currentAmplitude > peak):
				peak = currentAmplitude
				peakIndex = index

		#Translate index into frequency, then append to peakFrequencies list
		peakFrequencies.append(frequencies[peakIndex])


	return times, peakFrequencies



def generateFingerprints(times, peakFrequencies, fingerPrintLength=1, samplingFrequency=44100):
	'''
	Generates fingerprints from a constellation map
	'''
	pass




filepath = 'SongFiles/Marble Machine_by Wintergatan.wav'
times, peaks = generateConstellationMap(filepath)


plt.plot(times, peaks)
plt.show()
