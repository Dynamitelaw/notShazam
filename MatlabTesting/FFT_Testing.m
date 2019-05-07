warning('off','all');

a = [100, 53, 29, 47, 30, 91, 69, 64, 50, 28, 8, 4, 45, 59, 30, 10, 74, 31, 24, 46, 71, 81, 92, 24, 93, 34, 52, 47, 5, 96, 81, 70];
%a = 1:16;
%a = [11, 85, 23, 33, 6, 90, 77, 61];
disp(a*2^7);
%a = [77, 61];
Y = fft(a);

Z = myFFT(a(shuffleIndexes(length(a))+1));

isSameArray = int64(real(Z)*100) == int64(real(Y)*100);
notSameArray = isSameArray == 0;
notSame = bi2de(notSameArray);
%disp(real(Y));
%disp(real(Z));
disp(["Error = ", notSame]);

floatingPointAccuracy = 7;
for i = 1:length(a)
    %value = num2fixpt(real(Z(i)), sfix(24), 2^(-floatingPointAccuracy));% * 2^(floatingPointAccuracy);
    %disp(value);
    %disp(real(Y(i))*2^floatingPointAccuracy);
    sprintf("%f", real(Y(i))*2^floatingPointAccuracy);
end