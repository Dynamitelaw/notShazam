%Parse N from global variables
filetext = fileread('../Hardware/global_variables.sv');
expr = '[^\n]*`define NFFT[^\n]*';
defineN = regexp(filetext,expr,'match');
defineN_array = split(defineN, ' ');
N = str2num([char(defineN_array(3))]);

%Generate shuffled indexes
disp('Generating shuffling indexes for input');

shuffledIndexes = shuffleIndexes(N);
fileID = fopen('../Hardware/GeneratedParameters/InputShuffledIndexes.txt','w');
for i = shuffledIndexes
   fprintf(fileID,'%s\n',dec2hex(i));
end

fclose(fileID);


%Generate Ks
disp('Generating Ks for all butterfly modules');

kArray = generateKs(N);
fileID = fopen('../Hardware/GeneratedParameters/Ks.txt','w');
[rows, columns] = size(kArray);
for row = 1:rows
   for k = kArray(row, :)
       fprintf(fileID,'%s\n',dec2hex(k));
   end
end

fclose(fileID);


%Generate coefficients
disp('Generating complex coefficients');

expr = '[^\n]*`define SFFT_FIXED_POINT_ACCURACY[^\n]*'; %Parse floating point accuracy from global variables
defineFPA = regexp(filetext,expr,'match');
defineFPA_array = split(defineFPA, ' ');
floatingPointAccuracy = str2num([char(defineFPA_array(3))]);

realFileID = fopen('../Hardware/GeneratedParameters/realCoefficients.txt','w');
imaginaryFileID = fopen('../Hardware/GeneratedParameters/imaginaryCoefficients.txt','w');

for k = 0:N/2-1
   if k == 0
       k = 0.00000001;
   end
   w =  exp(-2i*pi*k/N);
   realCoef = uint32(num2fixpt(real(w), ufix(floatingPointAccuracy+1), 2^(-floatingPointAccuracy)) * 2^(floatingPointAccuracy));
   imagCoef = uint32(num2fixpt(imag(w), ufix(floatingPointAccuracy+1), 2^(-floatingPointAccuracy)) * 2^(floatingPointAccuracy));
     
   fprintf(realFileID,'%s\n',dec2hex(realCoef, (floatingPointAccuracy+1)/4));
   fprintf(imaginaryFileID,'%s\n',dec2hex(imagCoef, (floatingPointAccuracy+1)/4));
   
   disp(w);
   disp(q2dec([dec2hex(realCoef, (floatingPointAccuracy+1)/4)], 0, floatingPointAccuracy));
   disp(q2dec([dec2hex(imagCoef, (floatingPointAccuracy+1)/4)], 0, floatingPointAccuracy));
end

fclose(realFileID);
fclose(imaginaryFileID);


%Generate butterfly connection indexes
disp('Generating connection indexes');

aFileID = fopen('../Hardware/GeneratedParameters/aIndexes.txt','w');
bFileID = fopen('../Hardware/GeneratedParameters/bIndexes.txt','w');

stages = log2(N);
modulesPerStage = N/2;
for stage = 0:stages-1
    for module = 0:modulesPerStage-1
        indexA = bi2de(circshift(de2bi(2*module, stages), stage));
        indexB = bi2de(circshift(de2bi(2*module+1, stages), stage));
        
        fprintf(aFileID, '%s\n', dec2hex(indexA));
        fprintf(bFileID, '%s\n', dec2hex(indexB));
    end
end

fclose(aFileID);
fclose(bFileID);