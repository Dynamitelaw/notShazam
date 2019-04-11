function FFT = myFFT(x)
    N = length(x);
    stages = log2(N);
    modulesPerStage = N/2;
    stageOutputBuffer = [1:N]
    for stage = 1:stages
        disp(stageOutputBuffer);
    end
end