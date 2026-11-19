%% run_rx_hardware.m (全打印无盲区版)
clear; clc; close all;
addpath(genpath('project_root'));
warning('off', 'comm:SymbolSynchronizer:SymbolDropping'); 

P = params('overair');
P.basebandRate    = 250e3;  
P.rxFrameLength   = 2^9;    % 512点，不溢出
P.rxGain          = 10;     % 防饱和

try, release(sdrrx('Pluto')); catch, end
pause(1);
rxRadio = sdrrx('Pluto', 'CenterFrequency', P.centerFreq, 'BasebandSampleRate', P.basebandRate, ...
    'SamplesPerFrame', P.rxFrameLength, 'OutputDataType', 'double', 'GainSource', 'Manual', 'Gain', P.rxGain);

rxFilt = comm.RaisedCosineReceiveFilter('RolloffFactor', P.rolloff, 'FilterSpanInSymbols', P.span, 'InputSamplesPerSymbol', P.sps, 'DecimationFactor', 1);
cfoComp = comm.CoarseFrequencyCompensator('Modulation', P.modulation, 'FrequencyResolution', 100, 'SampleRate', P.basebandRate);
symSync = comm.SymbolSynchronizer('TimingErrorDetector', 'Gardner (non-data-aided)', 'Modulation', 'PAM/PSK/QAM', 'SamplesPerSymbol', P.sps, 'NormalizedLoopBandwidth', 0.05);
rxCarr = comm.CarrierSynchronizer('Modulation', P.modulation, 'SamplesPerSymbol', 1, 'NormalizedLoopBandwidth', 0.05);
demodObj = comm.QPSKDemodulator('BitOutput', true);

bitBuffer = []; 
iter = 0;

fprintf('=== RX 启动！只要找到包头，就打印 CRC 结果 ===\n');

try
    while true
        iter = iter + 1;
        try, [rxWave, ~, ~] = rxRadio(); catch, continue; end
        if max(abs(rxWave)) < 1e-6, continue; end
        
        rxWave = rxWave - mean(rxWave);
        rxWave = rxWave / (max(abs(rxWave)) + 1e-6) * 0.5; 
        
        rxMF = rxFilt(rxWave);
        rxMF = cfoComp(rxMF);
        [rxSym, ~] = symSync(rxMF);    
        [rxSym, ~] = rxCarr(rxSym);    
        rxBits = demodObj(rxSym);      
        
        bitBuffer = [bitBuffer, rxBits(:).'];                        
        if numel(bitBuffer) > 2e6, bitBuffer = bitBuffer(end - 2e6 + 1 : end); end
        
        frameStarts = frame_sync(bitBuffer, P);
        if isempty(frameStarts) && numel(bitBuffer) > 2000
            bitBuffer = bitBuffer(end - 1999 : end);
        else
            parse_limit = 20;
            while ~isempty(frameStarts) && parse_limit > 0
                parse_limit = parse_limit - 1;
                s = frameStarts(1);
                [payloadBytes, crcOK, frameLen] = frame_parser(bitBuffer, s, P);
                if frameLen == 0, break; end
                
                % 🚨 无论对错，一律打印！
                fprintf('找到包头！CRC=%d | 前8字节: %s\n', crcOK, num2str(payloadBytes(1:8)', '%02X '));
                
                % 只有对的才发声
                if crcOK && numel(payloadBytes) == 160
                    pcm = alaw_to_pcm16(payloadBytes);
                    sound(double(pcm)/32768 * 3, P.audioFs);
                    fprintf('✅ 播放真包！\n');
                end
                
                consume = s + frameLen - 1;
                if consume > 0 && consume <= numel(bitBuffer), bitBuffer(1:consume) = []; end
                frameStarts = frame_sync(bitBuffer, P);
            end
        end
        
        if mod(iter, 50) == 0
            pause(0.01);
        end
    end
catch ME
    fprintf('\n接收结束: %s\n', ME.message);
end
release(rxRadio);