function bufferfly = myButterfly(x, k, N)
    bufferfly = [0, 0];
    w = exp(-2*pi*i*k/N);
    bufferfly(1) = x(1) + w*x(2);
    bufferfly(2) = x(1) - w*x(2);
end