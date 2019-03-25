
################################
'''
This script is for testing the functionality of our recognition algorithm.
Algorithm and implimentation is based on this article: http://coding-geek.com/how-shazam-works/
'''
################################

import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal
from skimage.feature import peak_local_max
import numpy as np
from statistics import mean
from statistics import mode
from collections import Counter
import os


def generateConstellationMap(audioFilePath,
                             fftResolution=2048,
                             downsampleFactor=1,
                             sampleLength=False):
    '''
    Generates a constellation map for a given audio file.

    Parameters:
        <string> audioFilePath: path to the input audio file. File must be a
                     mono wave file with no metadata
        <int> fftResolution: number of frequencies to sample over (power of 2).
                     Defaults to 512
        <int> downsampleFactor: factor by which to downsample the timesteps of
                     the output. Defaults to 1
        <float> sampleLength: If defined, creates a constellation map only for
                     the first N seconds of the recording. Defaults to false.
                     Must be less than the length of the recording

    Returns:
        (times, peakFreaquencies)
        times: ndarray
        Array of time segments
        peakFrequencies: ndarray
        Array of peak frequencies (in Hz)
        '''

    # Read the wav file (mono)
    samplingFrequency, signalData = wavfile.read(audioFilePath)

    # Generate spectogram
    spectrogramData, frequencies, times, _ = plt.specgram(
        signalData, Fs=samplingFrequency, NFFT=fftResolution, noverlap=fftResolution/2, scale_by_freq=False)

    spectrogramData = 10. * np.log10(spectrogramData)

    plt.clf()
    plt.imshow(spectrogramData)

    #spectrogramData = np.transpose(spectrogramData)
    peaks = peak_local_max(spectrogramData, min_distance=50)
    plt.scatter(peaks[:,1], peaks[:,0])
    #plt.show()

    peaks = [tuple(row) for row in peaks]
    peaks = sorted(list(set(peaks)),key=lambda row: row[1])

    return peaks



def generateFingerprints(points, songID):
    '''
    Generates fingerprints from a constellation map.
    Returns fingerprints as a list.
    '''

    # Create target zones
    targetZoneDuration = 5
    targetZones = []
    for i in range(0, len(points), 1):
        zone = []
        for j in range(1, len(points) - i):
            if points[i+j][1] - points[i][1] <= targetZoneDuration:
                zone.append(points[i+j])
            else:
                break
        targetZones.append(zone)

    # Generate fingerprints
    fingerprints = []
    for t in range(0, len(points)):
        targetZone = targetZones[t]
        anchorPoint = points[t]
        anchorFrequency = anchorPoint[0]
        anchorTimepoint = anchorPoint[1]

        for point in targetZone:
            pointFrequency = point[0]
            timeDelta = point[1] - anchorTimepoint
            pointFingerprint = (anchorFrequency, pointFrequency, timeDelta)
            fingerprints.append((pointFingerprint, (songID, anchorTimepoint)))

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
        # print(possibleMatches)
        return str(Counter(possibleMatches).most_common())
    else:
        return "UNKNOWN"


def main():
    '''
    Test our algorithm on the noisy sample tracks in the "InputFiles" folder.
    Uses the songs in the "SongFiles" folder as the library to search against.
    '''

    # Generates a hash table (dictionary) for the song library, using fingerprints as the hash (key) and the songID and timepoints as the data points
    print("____________________________________________")
    print("Generating fingerprints for song library...")
    hashTable = {}
    songFileList = os.listdir("SongFiles")
    for songFile in songFileList:
        print("   " + songFile)
        peaks = generateConstellationMap("SongFiles/"+songFile, downsampleFactor=4)
        fingerprints = generateFingerprints(peaks, songFile.split("_")[0])

        for fingperprint in fingerprints:
            hashAddress = fingperprint[0]
            songData = fingperprint[1]

            if hashAddress in hashTable:  # fingerprint already exists
                hashTable[hashAddress].append(songData)
            else:
                hashTable[hashAddress] = [songData]  # create new list of possible matches

    # Try to identify noisy samples
    print("____________________________________________")
    print("Identifying samples...")
    songFileList = os.listdir("InputFiles")
    for songFile in songFileList:
        peaks = generateConstellationMap("InputFiles/"+songFile, downsampleFactor=4, sampleLength=20)  #try to identify on first 20 seconds of sample
        sampleFingerprints = generateFingerprints(peaks, songFile.split("_")[0])
        songID = identifySample(sampleFingerprints, hashTable)
        print("   " + songFile + " => " + songID)


main()
