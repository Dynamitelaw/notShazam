
################################
'''
This script is for testing the functionality of our recognition algorithm.
Algorithm and implimentation is based on this article: http://coding-geek.com/how-shazam-works/
'''
################################

import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal
import numpy as np
from statistics import mean 
from statistics import mode
import os


def generateConstellationMap(audioFilePath, fftResolution=512, downsampleFactor=1, sampleLength=False):
	'''
	Generates a constellation map for a given audio file.

	Parameters:
		<string> audioFilePath: path to the input audio file. File must be a mono wave file with no metadata
		<int> fftResolution: number of frequencies to sample over (power of 2). Defaults to 512
		<int> downsampleFactor: factor by which to downsample the timesteps of the output. Defaults to 1
		<float> sampleLength: If defined, creates a constellation map only for the first N seconds of the recording. Defaults to false. Must be less than the length of the recording

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
	if (sampleLength):
		spectrogramData = spectrogramData[0:int(sampleLength*samplingFrequency)]
		times = times[0:int(sampleLength*samplingFrequency)]

	#Bin frequencies in logarithmic bands
	numberOfBins = 6
	bins = [len(frequencies)]
	for i in range(1, numberOfBins, 1):
		binBoundary = int(len(frequencies) / (2**i))
		bins = [binBoundary] + bins
	bins = [0] + bins

	#Find the peak frequencies in the spectogram
	returnTimes = []
	peakFrequencies = []
	for s in range(0, len(spectrogramData), downsampleFactor):
		sample = spectrogramData[s]
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
			binPeaks.append((frequencies[bins[b]:bins[b+1]][peakIndex], currentAmplitude))

		#Determine which peaks in which bins to keep
		averageAmplitude = sum([i[1] for i in binPeaks])/numberOfBins
		filteredFrequencyPeaks = []
		for fBin in binPeaks:
			if (fBin[1] > averageAmplitude):
				filteredFrequencyPeaks.append(fBin[0])  #Include bin peak if it's amplitude is larger than the average amplitude of the bin peaks for this sample
		
		peakFrequencies.append(filteredFrequencyPeaks)
		returnTimes.append(times[s])
	
	return returnTimes, peakFrequencies



def generateFingerprints(times, peakFrequencies, songID):
	'''
	Generates fingerprints from a constellation map.
	Returns fingerprints as a list.
	'''

	#Reorganize constellation inputs into a 1D list of ordered points (frequency, time)
	points = []
	for i in range(0, len(peakFrequencies), 1):
		peaks = peakFrequencies[i]
		for p in peaks:
			points.append((p, times[i]))

	#Create target zones
	targetZoneSize = 5  #number of points to include in each target zone 
	targetZones = []
	for i in range(0, len(points)-targetZoneSize, 1):
		targetZones.append(points[i:i+targetZoneSize])

	#Generate fingerprints
	anchorPointSeperation = 5  #How far back the anchor point is for each target zone (in terms of the order of the points)
	fingerprints = []
	for t in range(anchorPointSeperation, len(targetZones), 1):
		targetZone = targetZones[t]
		anchorPoint = targetZones[t - anchorPointSeperation][0]
		anchorFrequency = anchorPoint[0]
		anchorTimepoint = anchorPoint[1]

		for point in targetZone:
			pointFrequency = point[0]
			timeDelta = point[1] - anchorTimepoint
			pointFingerprint = (anchorFrequency, pointFrequency, timeDelta)
			fingerprints.append((pointFingerprint,(songID, anchorTimepoint)))

	return fingerprints
	

def identifySample(sampleFingerprints, hashTable):
	'''
	Identify the sample based on the fingerprints in the hashtable.
	Returns the songID as a string.
	'''
	possibleMatches = []
	for fingerprint in sampleFingerprints:
		if fingerprint[0] in hashTable:
			for songData in hashTable[fingerprint[0]]:
				possibleMatches.append(songData[0])

	if (len(possibleMatches)):
		#print(possibleMatches)
		return mode(possibleMatches)
	else:
		return "UNKNOWN"


def main():
	'''
	Test our algorithm on the noisy sample tracks in the "InputFiles" folder.
	Uses the songs in the "SongFiles" folder as the library to search against.
	'''

	#Generates a hash table (dictionary) for the song library, using fingerprints as the hash (key) and the songID and timepoints as the data points
	print("____________________________________________")
	print("Generating fingerprints for song library...")
	hashTable = {}
	songFileList = os.listdir("SongFiles")
	for songFile in songFileList:
		print("   " + songFile)
		times, peaks = generateConstellationMap("SongFiles/"+songFile, downsampleFactor=4)
		fingerprints = generateFingerprints(times, peaks, songFile.split("_")[0])

		for fingperprint in fingerprints[:24]:
			hashAddress = fingperprint[0]
			songData = fingperprint[1]

			if hashAddress in hashTable:  #fingerprint already exists
				hashTable[hashAddress].append(songData)
			else:
				hashTable[hashAddress] = [songData]  #create new list of possible matches

	#Try to identify noisy samples
	print("____________________________________________")
	print("Identifying samples...")
	songFileList = os.listdir("InputFiles")
	for songFile in songFileList:
		times, peaks = generateConstellationMap("InputFiles/"+songFile, downsampleFactor=4, sampleLength=20)  #try to identify on first 20 seconds of sample
		sampleFingerprints = generateFingerprints(times, peaks, songFile.split("_")[0])
		songID = identifySample(sampleFingerprints, hashTable)
		print("   " + songFile + " => " + songID)


main()
