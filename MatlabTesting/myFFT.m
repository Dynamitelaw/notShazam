function FFT = myFFT(x)
    N = length(x);
    stages = log2(N);
    modulesPerStage = N/2;
    stageInputBuffer = [0:N-1];
    stageOutputBuffer = x;
    for stage = 0:stages-1
        disp("==================");
        stageInputBuffer = stageOutputBuffer;
        for module = 0:modulesPerStage-1
            mask = [zeros(1, stages-1),  ones(1, 50)];
            p = [mask(1+stage:length(mask)), zeros(1, stage) ];
            p = p(1:stages);
            k = p & de2bi(module, stages);
            k = bi2de(k);
            %disp(k);
                
            index0 = bi2de(circshift(de2bi(2*module, stages), stage));
            index1 = bi2de(circshift(de2bi(2*module+1, stages), stage));
            disp([index0 , index1, k]);
            
            moduleOutput = myButterfly([stageInputBuffer(index0+1), stageInputBuffer(index1+1)], k, N);
            %moduleOutput = myButterfly([stageInputBuffer(index0+1), stageInputBuffer(index1+1)], k, 2^(stage+1));
            stageOutputBuffer(index0+1) = moduleOutput(1);
            stageOutputBuffer(index1+1) = moduleOutput(2);
        end
        %disp(stageOutputBuffer);
    end
    
    FFT = stageOutputBuffer;
end