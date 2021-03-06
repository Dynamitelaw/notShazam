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
    
    print(songName)

    fmag = open(songName[0:-4]+".mag", 'w')
    freal = open(songName[0:-4]+".real", 'w')

    length = len(signalData) - (len(signalData) % fftResolution)

    i = 0
    while i < length - fftResolution/2:
        
        fft_temp = np.fft.fft(signalData[i:i+fftResolution])

        j = 0
        while j < fftResolution/2:
            #Magnitude/ Absolute Value
            fmag.write(str(np.abs(fft_temp[j])))
            fmag.write(" ")
            #Real Part of the FFT 
            freal.write(str(np.abs(np.real(fft_temp[j]))))
            freal.write(" ")
            j = j + 1
        
        fmag.write("\n")
        freal.write("\n")
        
        i = i + fftResolution/2
        
        
    fmag.close()
    freal.close()


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
