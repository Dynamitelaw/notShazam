function FFT = myFFT(x)
    N = length(x);
    stages = log2(N);
    modulesPerStage = N/2;
    stageInputBuffer = [0:N-1];
    stageOutputBuffer = x;
    for stage = 0:stages-1
        %disp("==================");
        stageInputBuffer = stageOutputBuffer;
        for module = 0:modulesPerStage-1
            k = 0;
            if stage == 0
                k = 0;
            else
                k = mod(module, 2^stage);
            end
            %disp(k);
            index0 = bi2de(circshift(de2bi(2*module, stages), stage));
            index1 = bi2de(circshift(de2bi(2*module+1, stages), stage));
            
            moduleOutput = myButterfly([stageInputBuffer(index0+1), stageInputBuffer(index1+1)], k, 2^(stage+1));
            stageOutputBuffer(index0+1) = moduleOutput(1);
            stageOutputBuffer(index1+1) = moduleOutput(2);
        end
        %disp(stageOutputBuffer);
    end
    
    FFT = stageOutputBuffer;
end