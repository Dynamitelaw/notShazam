function kArrays = generateKs(N)
    stages = log2(N);
    modulesPerStage = N/2;
    kArrays = zeros(stages, modulesPerStage);
    
    for stage = 0:stages-1
        stageKArray = [1:modulesPerStage];
        for module = 0:modulesPerStage-1
            mask = [zeros(1, stages-1),  ones(1, 50)];
            p = [mask(1+stage:length(mask)), zeros(1, stage) ];
            p = p(1:stages);
            k = p & de2bi(module, stages);
            k = bi2de(k);
            stageKArray(module+1) = k;
        end
        kArrays(stage+1,:) = stageKArray;
    end
end