
#import the pyplot and wavfile modules 

import matplotlib.pyplot as plt

from scipy.io import wavfile
from scipy import signal
import numpy as np
from statistics import mean 
 


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

	#Bin frequencies in logarithmic bands
	numberOfBins = 6
	bins = [len(frequencies)]
	for i in range(1, numberOfBins, 1):
		binBoundary = int(len(frequencies) / (2**i))
		bins = [binBoundary] + bins
	bins = [0] + bins

	#Find the peak frequencies in the spectogram
	peakFrequencies = []
	for sample in spectrogramData:
		#Find the peaks for each frequency bin
		binPeaks = []
		for b in range(0, numberOfBins, 1):
			subSample = sample[bins[b]:bins[b+1]]

			#Find the index of the peak frequency in this bin
			peak = subSample[0]
			peakIndex = 0

			for index in range(1, len(subSample), 1):
				currentAmplitude = subSample[index]
				if (currentAmplitude > peak):
					peak = currentAmplitude
					peakIndex = index

			#Translate index into frequency, then append to samplePeaks list
			binPeaks.append((frequencies[peakIndex], currentAmplitude))

		#Determine which peaks in which bins to keep
		averageAmplitude = sum([i[1] for i in binPeaks])/numberOfBins
		filteredFrequencyPeaks = []
		for fBin in binPeaks:
			if (fBin[1] > averageAmplitude):
				filteredFrequencyPeaks.append(fBin[0])  #Include bin peak if it's amplitude is larger than the average amplitude of the bin peaks for this sample
		
		peakFrequencies.append(filteredFrequencyPeaks)
	
	return times, peakFrequencies



def generateFingerprints(times, peakFrequencies, fingerPrintLength=1, samplingFrequency=44100):
	'''
	Generates fingerprints from a constellation map. Each fingerprint
	'''
	pass




filepath = 'SongFiles/Marble Machine_by Wintergatan.wav'
times, peaks = generateConstellationMap(filepath)

print(peaks[50:53])

#plt.plot(times, peaks)
#plt.show()
