function [rxSym, phaseErr] = phase_track(rxSym, P)
persistent carrSync syncTag
tagNow = sprintf('%.6g_%s', P.sps, P.modulation);

if isempty(carrSync) || ~strcmp(syncTag, tagNow)
    if ~isempty(carrSync), release(carrSync); end
    carrSync = comm.CarrierSynchronizer( ...
        'Modulation',              P.modulation, ...
        'SamplesPerSymbol',        1, ...
        'NormalizedLoopBandwidth', 0.05); 
    syncTag = tagNow; 
end
[rxSym, phaseErr] = carrSync(rxSym);
end