warning('off','all');

a = [11, 85, 23, 33, 6, 90, 77, 61, 11, 85, 23, 33, 6, 90, 77, 61];
%a = 1:16;
%a = [11, 85, 23, 33, 6, 90, 77, 61];
Y = fft(a);

Z = myFFT(a(shuffleIndexes(length(a))+1));

isSameArray = int64(real(Z)*100) == int64(real(Y)*100);
notSameArray = isSameArray == 0;
notSame = bi2de(notSameArray);
%disp(Y);
%disp(Z);
disp(["Error = ", notSame]);
