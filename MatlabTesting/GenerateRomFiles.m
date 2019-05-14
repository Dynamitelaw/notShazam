%Parse N from global variables
filetext = fileread('../Hardware/global_variables.sv');
expr = '[^\n]*`define NFFT[^\n]*';
defineN = regexp(filetext,expr,'match');
defineN_array = split(defineN, ' ');
N = str2num([char(defineN_array(3))]);

disp(N);
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

real_pairs = zeros(N/2, 2);
imag_pairs = zeros(N/2, 2);

for k = 0:N/2-1
   %if k == 0
   %    k = 0.000001;
   %end
   w =  exp(-2i*pi*k/N);
   realCoef = uint32(num2fixpt(real(w), ufix(floatingPointAccuracy+1), 2^(-floatingPointAccuracy)) * 2^(floatingPointAccuracy));
   if k == 0
   	realCoef = uint32((1 - 2^(-floatingPointAccuracy))*2^(floatingPointAccuracy));
   end
   imagCoef = uint32(num2fixpt(imag(w), ufix(floatingPointAccuracy+1), 2^(-floatingPointAccuracy)) * 2^(floatingPointAccuracy));
   
   fprintf(realFileID,'%s\n',dec2hex(realCoef, (floatingPointAccuracy+1)/4));
   fprintf(imaginaryFileID,'%s\n',dec2hex(imagCoef, (floatingPointAccuracy+1)/4));
   
   %disp('========================')
   %disp(k);
   %disp(w);
   %disp(q2dec([dec2hex(realCoef, (floatingPointAccuracy+1)/4)], 0, floatingPointAccuracy));
   %disp(q2dec([dec2hex(imagCoef, (floatingPointAccuracy+1)/4)], 0, floatingPointAccuracy));
   
   real_pair = [real(w), q2dec([dec2hex(realCoef, (floatingPointAccuracy+1)/4)], 0, floatingPointAccuracy)];
   imag_pair = [imag(w), q2dec([dec2hex(imagCoef, (floatingPointAccuracy+1)/4)], 0, floatingPointAccuracy)];
   
   %disp(real_pair);
   %disp(imag_pair);

   
   real_pairs(k+1, :) = real_pair;
   imag_pairs(k+1, :) = imag_pair;
end

real_err = real_pairs(:, 1) - real_pairs(:, 2);
imag_err = imag_pairs(:, 1) - imag_pairs(:, 2);

real_err = abs(real_err);
imag_err = abs(imag_err);

real_max = max(real_err);
real_min = min(real_err);
real_avg = mean(real_err);

imag_max = max(imag_err);
imag_min = min(imag_err);
imag_avg = mean(imag_err);

%disp('========================')
disp(["Real Error Max:", real_max]);
%disp(["Real Error Min:", real_min]);
disp(["Real Error Avg:", real_avg]);
disp('')
disp(["Imag Error Max:", imag_max]);
%disp(["Imag Error Min:", imag_min]);
disp(["Imag Error Avg:", imag_avg]);
%disp('========================')

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
