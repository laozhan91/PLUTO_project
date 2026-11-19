function isi_dB = measure_isi(P)
    % 发射一个脉冲看响应
    txFilter = comm.RaisedCosineTransmitFilter('RolloffFactor',P.rolloff, ...
        'FilterSpanInSymbols',P.span,'OutputSamplesPerSymbol',P.sps);
    rxFilter = comm.RaisedCosineReceiveFilter('RolloffFactor',P.rolloff, ...
        'FilterSpanInSymbols',P.span,'InputSamplesPerSymbol',P.sps,'DecimationFactor',P.sps);
    
    impulse = [1; zeros(100,1)];
    txPulse = txFilter(impulse);
    rxPulse = rxFilter(txPulse);
    
    [peak, idx] = max(abs(rxPulse));
    sideLobes = rxPulse; sideLobes(idx) = 0;
    isi_dB = 20*log10(max(abs(sideLobes)) / peak);
end