function [rxSym, timingErr, lockIndex] = timing_sync(rxMF, P)
persistent symSync syncTag
tagNow = sprintf('%.6g_%.6g_%s', P.sps, P.basebandRate, P.modulation);

if isempty(symSync) || ~strcmp(syncTag, tagNow)
    if ~isempty(symSync), release(symSync); end
    symSync = comm.SymbolSynchronizer( ...
        'TimingErrorDetector','Gardner (non-data-aided)', ...
        'Modulation','PAM/PSK/QAM', ...
        'SamplesPerSymbol', P.sps, ...
        'NormalizedLoopBandwidth', 0.02);
    syncTag = tagNow; 
end
[rxSym, timingErr] = symSync(rxMF);
lockIndex = 0;
end