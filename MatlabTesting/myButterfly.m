function bufferfly = myButterfly(x, k, N)
    bufferfly = [0, 0];
    w = exp(-2i*pi*k/N);
    %w = real(w);
    bufferfly(1) = x(1) + w*x(2);
    bufferfly(2) = x(1) - w*x(2);
    
    %bufferfly(1) = x(2);
    %bufferfly(2) = x(1);
end