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

def generateFFT(audioDirPath, songName, fftResolution,
                             downsampleFactor, sampleLength):

    # Read the wav file (mono)
    samplingFrequency, signalData = wavfile.read(audioDirPath+songName)
    signalData = signalData[0:len(signalData):downsampleFactor]
    # Generate spectogram
    spectrogramData, frequencies, times, _ = plt.specgram(signalData, 
            NFFT=fftResolution,  Fs=samplingFrequency, noverlap=fftResolution/2, 
            mode='magnitude', scale='linear', scale_by_freq=False)
  
    print(songName)
    print("Spectrogram size:" + str(spectrogramData.shape[0]) + " " + 
            str(spectrogramData.shape[1]));
    
    f = open(songName[0:-4], 'w')
    
    for i in range(0, spectrogramData.shape[0] - 1):
        for j in range(0, spectrogramData.shape[1] - 1):
            f.write((str(spectrogramData[i,j]) + " "))
        f.write("\n")
    
    f.close()


def main():
    '''
    Test our algorithm on the noisy sample tracks in the "InputFiles" folder.
    Uses the songs in the "SongFiles" folder as the library to search against.
    '''

    songFileList = os.listdir("SongFiles")
    for songFile in songFileList:
        generateFFT("SongFiles/", songFile, 128, 4, 20)
    songFileList = os.listdir("InputFiles")
    for songFile in songFileList:
        generateFFT("InputFiles/", songFile, 128, 4, 20)

main()
