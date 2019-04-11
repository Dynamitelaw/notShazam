a = [11, 85, 23, 33, 6, 90, 77, 61];
%a = [11, 85];
Y = fft(a);

disp(Y);
%Z = myButterfly(a, 0, 2);
%disp(Z);
myFFT(a);
