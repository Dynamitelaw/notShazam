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
    signalData = signalData[0:len(signalData):4]
    # Generate spectogram
    frequencies, times, spectrogramData = signal.spectrogram(signalData,
            fs=samplingFrequency, nperseg=fftResolution, noverlap=fftResolution/2, 
            nfft=fftResolution, mode='complex', scaling='spectrum')

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
        #generateFFT("SongFiles/", songFile, 256)
    songFileList = os.listdir("InputFiles")
    #for songFile in songFileList:
        #generateFFT("InputFiles/", songFile, 256)
    f.close()

main()
