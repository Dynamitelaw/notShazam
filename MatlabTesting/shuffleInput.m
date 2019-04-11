function shuffledArray = shuffleInput(x)
    N = length(x);
    inputIndexes = 1:N;
    outputIndexes = 1:N;
    
    numberOfIterations = log2(N)-1;
    
    for i = 0:numberOfIterations-1
       disp("=============");
       %i
       for subArray = 0:2^(i-1)
          %disp(subArray);
          inputSubset = inputIndexes(subArray*(N/2^i)+1:(subArray+1)*(N/2^i));
          disp(inputSubset);
          outputSubset = 1:length(inputSubset);
          for index = 0:length(inputSubset)-1
             if mod(index,2) == 0
                 outputSubset(uint8(index/2)+1) = inputSubset(index+1);
             else
                 outputSubset(length(inputSubset)/2+uint8(index/2)) = inputSubset(index+1);
             end
             
          end
          
          disp(outputSubset);
          disp(" ");
       end
        
    end
end