################################
'''
This script is for temporarily generating the
spectrogram for our recognition algorithm.
'''
################################

import matplotlib.pyplot as plt
from scipy.io import wavfile
from scipy import signal
import numpy as np
import os

def generateFFT(audioDirPath, songName, fftResolution):

    # Read the wav file (mono)
    samplingFrequency, signalData = wavfile.read(audioDirPath+songName)
    # Generate spectogram
    #print(signalData[:8])
    signalData = np.mean(signalData[:(len(signalData)//2)*2].reshape(-1, 2), axis=1)
    #print(signalData[:8])
    samplingFrequency /= 2
    frequencies, times, spectrogramData = signal.spectrogram(signalData,
        fs=samplingFrequency, nperseg=fftResolution, noverlap=fftResolution/2,
        nfft=fftResolution, window='boxcar', mode='complex', scaling='spectrum')

    print(songName)
    print("Spectrogram size:" + str(spectrogramData.shape[0]) + " " +
            str(spectrogramData.shape[1]));

    f = open(songName[0:-4], 'w')

    for i in range(0, spectrogramData.shape[0] - 1):
        for j in range(0, spectrogramData.shape[1] - 1):
            f.write((str(np.real(spectrogramData[i,j])) + " "))
        f.write("\n")

    f.close()


def main():
    '''
    Test our algorithm on the noisy sample tracks in the "InputFiles" folder.
    Uses the songs in the "SongFiles" folder as the library to search against.
    '''

    f = open("song_list.txt", 'w');
    songFileList = os.listdir("SongFiles")
    for songFile in songFileList:
        f.write(songFile[0:-4] + "\n");
        generateFFT("SongFiles/", songFile,  512)
    songFileList = os.listdir("InputFiles")
    for songFile in songFileList:
        generateFFT("InputFiles/", songFile, 512)
    f.close()

main()
