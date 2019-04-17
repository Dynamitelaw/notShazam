function shuffleIndexes = shuffleIndexes(N)
    inputIndexes = 0:N-1;
    outputIndexes = 0:N-1;
    n = log2(N);
    for index = inputIndexes
        bitReversed = bi2de(de2bi(index, n), 'left-msb');
        outputIndexes(index+1) = bitReversed;
    end
    
    shuffleIndexes = outputIndexes;
end