function [rxBitsQuad, rxSym, metrics] = rx_chain(rxWaveform, P)
persistent rxFilt symSync rxCarr demodObj cfoComp
if isempty(rxFilt)
    rxFilt = comm.RaisedCosineReceiveFilter('RolloffFactor', P.rolloff, ...
        'FilterSpanInSymbols', P.span, 'InputSamplesPerSymbol', P.sps, 'DecimationFactor', 1);
    symSync = comm.SymbolSynchronizer('TimingErrorDetector', 'Gardner (non-data-aided)', ...
        'Modulation', 'PAM/PSK/QAM', 'SamplesPerSymbol', P.sps, 'NormalizedLoopBandwidth', 0.01);
    rxCarr = comm.CarrierSynchronizer('Modulation', P.modulation, ...
        'SamplesPerSymbol', 1, 'NormalizedLoopBandwidth', 0.01, 'DampingFactor', 0.707);
    cfoComp = comm.CoarseFrequencyCompensator('Modulation', 'QPSK', ...
        'SampleRate', P.basebandRate, 'FrequencyResolution', 100); 
    demodObj = comm.QPSKDemodulator('BitOutput', true);
end

release(rxFilt); release(symSync); release(rxCarr); release(cfoComp); release(demodObj);

rxWaveform = rxWaveform - mean(rxWaveform);
if max(abs(rxWaveform)) < 1e-5
    rxBitsQuad = {}; rxSym = []; metrics = struct(); return;
end

rxWaveform = rxWaveform / (sqrt(mean(abs(rxWaveform).^2)) + 1e-9) * 0.7;

[rxWaveform_comp, cfoEst] = cfoComp(rxWaveform);

rxMF = rxFilt(rxWaveform_comp);
[rxSym, timingErr] = symSync(rxMF);
[rxSym, phaseErr]   = rxCarr(rxSym);

% 解调 4 种旋转
rxBitsQuad = cell(1, 4);
rxBitsQuad{1} = demodObj(rxSym);
rxBitsQuad{2} = demodObj(rxSym * (-1j));
rxBitsQuad{3} = demodObj(rxSym * (-1));
rxBitsQuad{4} = demodObj(rxSym * (1j));

metrics = struct('timingErr', timingErr, 'phaseErr', phaseErr, 'rxSym', rxSym, 'cfoEst', cfoEst);
end