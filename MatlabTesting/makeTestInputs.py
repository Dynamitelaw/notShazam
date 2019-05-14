import math
import random

times = []
SamplingFrequency = 512
timeStep = 1.0/SamplingFrequency
for i in range(SamplingFrequency):
	times.append(i*timeStep)

amplitudes = []
amplitudesMatlab = []
frequency = 50
for time in times:
	randomNum = (random.random())
	amplitude = int(0.7*(2**6)*math.sin(2*3.141562653*frequency*time) + 2**7)
	amplitude = int(0.7*(2**6)*randomNum)
	amplitudes.append(amplitude)
	
	amplitudeMatlab = int(0.7*(2**6)*math.sin(2*3.141562653*frequency*time) + 2**7)
	amplitudeMatlab = int(0.7*(2**6)*randomNum)
	amplitudesMatlab.append(amplitudeMatlab)

outputStrings = []
outputStringsMatlab = []
for i in range(SamplingFrequency):
	amplitude = amplitudes[i]
	outputString = "24'd" + str(amplitude)
	if (i != 0):
		outputString += ", "
		
	if (i % 30 == 0):
		outputString += "\n"
	outputStrings.append(outputString)
	
	amplitudeMatlab = amplitudesMatlab[i]
	outputStringsMatlab.append(str(amplitudeMatlab) + " ")

finalString = "reg [23:0] testWave [" + str(SamplingFrequency-1) + ":0] = '{"
for i in range(SamplingFrequency-1,-1,-1):
	finalString += outputStrings[i]
	
finalString += "};"

File = open("testInput.txt", 'w')
File.write(finalString)
File.close()

File = open("testInput_Matlab.txt", 'w')
for string in outputStringsMatlab:
	File.write(string)
File.close()

#print(amplitudesMatlab)
#print(finalString)
