
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
from collections import Counter, defaultdict, namedtuple
import os
import math
import heapq


def generateConstellationMap(audioFilePath,
                             fftResolution=256,
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
    signalData = signalData[0:len(signalData):4]

    # Generate spectogram
    spectrogramData, frequencies, times, _ = plt.specgram(
        signalData, Fs=samplingFrequency, NFFT=fftResolution, noverlap=fftResolution/2, scale_by_freq=False)


    #spectrogramData = 10. * np.log10(spectrogramData)

    plt.clf()
    plt.imshow(spectrogramData)

    #spectrogramData = np.transpose(spectrogramData)
    peaks = get_peaks_max_bins(spectrogramData, fftResolution)
    #peaks = get_peaks_skimage(spectrogramData)
    #plt.scatter(peaks[:,1], peaks[:,0])
    #plt.show()

    return peaks


def get_peaks_skimage(spectrogramData):
    peaks = peak_local_max(spectrogramData, min_distance=50)
    peaks = [tuple(row) for row in peaks]
    peaks = sorted(list(set(peaks)),key=lambda row: row[1])
    return peaks


def get_bins(n, nfft):
    bins_new = [0, 1, 4, 13, 24, 37, 116]
    bins = []
    j = 0
    for i in range(int(math.log2(nfft)) - n, int(math.log2(nfft))):
        bins.append(j)
        j += 2**i
    bins.append(int(nfft/2))
    print(bins)
    #print(bins_new)
    return bins


def prune_binned_peaks(peaks, NFFT, time_bin_size=50):
    bins = get_bins(6, NFFT)
    time = time_bin_size
    interval_peaks = defaultdict(list)
    pruned_peaks = []
    for peak in peaks:
        if peak.time > time:
            for binned_peaks in interval_peaks.values():
                if len(binned_peaks) != 0:
                    avg = mean(p.ampl for p in binned_peaks)
                    pruned_peaks += list(filter(lambda p: p.ampl > 1.5*avg, binned_peaks))
            interval_peaks.clear()
            time = time + time_bin_size

        interval_peaks[np.searchsorted(bins, peak.freq, side='right')].append(
            peak)
    print(len(pruned_peaks))
    return pruned_peaks


def get_peaks_max_bins(spectrogramData, NFFT, down=1):
    Peak = namedtuple('Peak', ['ampl', 'freq', 'time'])
    bins = get_bins(6, NFFT)
    sample = 0
    peaks = []
    for i in range(down, spectrogramData.shape[1] - down, down):
        fft_prev = spectrogramData[:, i-down]
        fft = spectrogramData[:, i]
        fft_next = spectrogramData[:, i+down]
        peak_bins = defaultdict(list)
        if fft[0] > fft[0+1] and fft[0] > fft_next[0] and fft[0] > fft_prev[0]:
            peak = Peak(ampl=fft[0], freq=0, time=sample)
            peak_bins[np.searchsorted(bins, peak.freq, side='right')].append(peak)
            pass
        for j in range(1, bins[-1]):
            if fft[j] > fft[j-1] and fft[j] > fft[j+1] \
                    and fft[j] > fft_next[j] and fft[j] > fft_prev[j]:
                peak = Peak(ampl=fft[j], freq=j, time=sample)
                peak_bins[np.searchsorted(bins, peak.freq, side='right')].append(peak)
        bin_peaks = [max(x, key=lambda p: p.ampl) for x in peak_bins.values()]
        if len(bin_peaks) == 0:
            continue
        avg_peak_ampl = mean([p.ampl for p in bin_peaks])
        for p in bin_peaks:
            if p.ampl >= .005*avg_peak_ampl:
                peaks.append(p)
        peak_bins.clear()
        bin_peaks.clear()
        sample += 1
    print(len(peaks))

    return [(p.freq, p.time) for p in prune_binned_peaks(peaks, NFFT)]


def get_peaks_all(spectrogramData, down=1):
    sample = 0
    peaks = []
    for i in range(down, spectrogramData.shape[1] - down, down):
        fft_prev = spectrogramData[:,i-down]
        fft = spectrogramData[:,i]
        fft_next = spectrogramData[:,i+down]
        for j in range(1, len(fft) - 1):
            if fft[j] > fft[j-1] and fft[j] > fft[j+1] \
                    and fft[j] > fft_next[j] and fft[j] > fft_prev[j]:
                peaks.append((j, sample))
        sample += 1
    return peaks


def get_peaks_avg(spectrogramData, down=1):
    learning = 0.2
    sample = 0
    peaks = []
    exp_avg = np.zeros(spectrogramData.shape[0])
    for i in range(down, spectrogramData.shape[1] - down, down):
        fft_prev = spectrogramData[:,i-down]
        fft = spectrogramData[:,i]
        fft_next = spectrogramData[:,i+down]
        for j in range(1, len(fft) - 1):
            if fft[j] > fft[j-1] and fft[j] > fft[j+1] \
                    and fft[j] > fft_next[j] and fft[j] > fft_prev[j] \
                    and fft[j] >= exp_avg[j]:
                peaks.append((j, sample))
            exp_avg[j] = fft[j] if exp_avg[j] == 0.0 \
                else exp_avg[j]*(1 - learning) + learning*fft[j]
        sample += 1
    print(len(peaks))
    return peaks

def generateFingerprints(points, songID):
    '''
    Generates fingerprints from a constellation map.
    Returns fingerprints as a list.
    '''
    # Create target zones by peaks
    targetZoneSize = 5  #number of points to include in each target zone
    targetZones = []
    for i in range(0, len(points)-targetZoneSize, 1):
        targetZones.append(points[i:i+targetZoneSize])

    # Create target zones by time
#   targetZoneDuration = 5
#   targetZones = []
#   for i in range(0, len(points), 1):
#       zone = []
#       for j in range(1, len(points) - i):
#           if points[i+j][1] - points[i][1] <= targetZoneDuration:
#               zone.append(points[i+j])
#           else:
#               break
#       targetZones.append(zone)

    # Generate fingerprints
    fingerprints = []
#    for t in range(0, len(points)): # CHANGE THIS
    for t in range(0, len(points)-targetZoneSize): # CHANGE THIS
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

        # print(possibleMatches)
    return Counter(possibleMatches).most_common()


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
        results = identifySample(sampleFingerprints, hashTable)
        if len(results) == 0:
            guess = "UNKNOWN"
            confidence = 0
        else:
            guess = results[0][0]
            if len(results) == 1:
                confidence = 1
            else:
                confidence = (results[0][1] - results[1][1])/results[0][1]
        print("   " + songFile + " => " + guess + " -\t confidence: " + str(confidence))


main()
