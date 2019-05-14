import math

times = []
SamplingFrequency = 512
timeStep = 1.0/SamplingFrequency
for i in range(SamplingFrequency):
	times.append(i*timeStep)

amplitudes = []
amplitudesMatlab = []
frequency = 16
for time in times:
	amplitude = int(0.7*(2**10)*math.sin(2*3.141562653*frequency*time) + 2**11)
	amplitudes.append(amplitude)
	
	amplitudeMatlab = int(0.7*(2**10)*math.sin(2*3.141562653*frequency*time) + 2**11)
	amplitudesMatlab.append(amplitudeMatlab)

outputStrings = []
outputStringsMatlab = []
for i in range(SamplingFrequency):
	amplitude = amplitudes[i]
	outputString = "24'd" + str(amplitude)
	if (i != SamplingFrequency-1):
		outputString += ", "
		
	if (i % 30 == 0):
		outputString += "\n"
	outputStrings.append(outputString)
	
	amplitudeMatlab = amplitudesMatlab[i]
	outputStringsMatlab.append(str(amplitudeMatlab) + " ")

finalString = "reg [23:0] testWave [" + str(SamplingFrequency-1) + ":0] = '{"
for string in outputStrings:
	finalString += string
	
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
