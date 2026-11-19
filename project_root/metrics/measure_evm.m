function evm_rms = measure_evm(rxSym, P)
    if strcmpi(P.modulation,'BPSK')
        refConst = [1; -1];
    else
        refConst = [1+1j; 1-1j; -1+1j; -1-1j] / sqrt(2);
    end
    evmObj = comm.EVM('ReferenceSignalSource','Estimated from reference constellation', ...
                      'ReferenceConstellation', refConst);
    evm_rms = evmObj(rxSym);
end