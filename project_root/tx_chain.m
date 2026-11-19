function [txWaveform, txBits, txSymbols] = tx_chain(P, inputBits)
    % 如果没有传入 inputBits，才用随机数（兼容你的纯仿真）
    if nargin < 2 || isempty(inputBits)
        txBits = randi([0 1], P.nBits, 1);
    else
        txBits = inputBits;
    end
    % 后面的调制、成型代码保持不变...
    % 2. 调制
    if strcmpi(P.modulation,'BPSK')
        modObj = comm.BPSKModulator('BitInput',true);
    else
        modObj = comm.QPSKModulator('BitInput',true);
    end
    txSymbols = modObj(txBits);
    
    % 3. 脉冲成型 (RRC)
    txFilt = comm.RaisedCosineTransmitFilter( ...
        'RolloffFactor',P.rolloff, ...
        'FilterSpanInSymbols',P.span, ...
        'OutputSamplesPerSymbol',P.sps, ...
        'Shape','Square root');
    txWaveform = txFilt(txSymbols);
end