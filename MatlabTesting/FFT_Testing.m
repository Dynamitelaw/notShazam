warning('off','all');

a = [11, 85, 23, 33, 6, 90, 77, 61];
%a = 1:16;
%a = [0, 1, 2, 3, 4, 5, 6, 7];
%k = shuffleInput(a);
%disp(k);
%a = [11, 85, 23, 33];
%a = [1: 2^5]
Y = fft(a);

disp(Y);
%Z = myButterfly(a, 0, 2);
%disp(Z);
%Z = myFFT([a(0+1), a(2+1), a(1+1), a(3+1)]);
%Z = myFFT([a(0+1), a(4+1), a(2+1), a(6+1), a(1+1), a(5+1), a(3+1), a(7+1)]);
Z = myFFT(shuffleInput(a));
disp(Z);

%module = 1;
%stages = 5;
%stage = 1;
%de2bi(2*module, stages)
%bi2de(circshift(de2bi(2*module, stages), 1*stage))
%bi2de(circshift(de2bi(2*module+1, stages), 1*stage))