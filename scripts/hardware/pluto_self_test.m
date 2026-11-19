%% run_rx_hardware.m (极简暴力出声版)
clear; clc; close all;
addpath(genpath('project_root'));

P = params('overair');
P.basebandRate    = 250e3;  
P.rxFrameLength   = 2^12;   
P.rxGain          = 45;     
P.audioVolumeGain = 8; % 放大音量

try, release(sdrrx('Pluto')); catch, end
pause(1);
rxRadio = sdrrx('Pluto', 'CenterFrequency', P.centerFreq, 'BasebandSampleRate', P.basebandRate, ...
    'SamplesPerFrame', P.rxFrameLength, 'OutputDataType', 'double', 'GainSource', 'Manual', 'Gain', P.rxGain);

bitBuffer = []; frameOK = 0; frameFail = 0;     
lastPayloadBytes = uint8([]); 
rxAudioBuffer = int16([]);

% 初始化基础画图
fig = figure('Name','实时波形','NumberTitle','off');
hPlot = plot(zeros(1, 1600), 'b');
ylim([-1 1]);

fprintf('=== RX 就绪！只要解出包，立刻发声并刷新波形 ===\n');
try
    while true
        try, [rxWave, ~, ~] = rxRadio(); catch, continue; end
        rxWave = rxWave - mean(rxWave);
        
        try, [rxBits, ~] = rx_chain(rxWave, P); catch, continue; end
        if isempty(rxBits), continue; end
        
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
                
                if crcOK
                    if isempty(lastPayloadBytes) || ~isequal(payloadBytes, lastPayloadBytes)
                        lastPayloadBytes = payloadBytes;
                        rxAudioBuffer = [rxAudioBuffer; alaw_to_pcm16(payloadBytes)];            
                        frameOK = frameOK + 1;
                    end
                    
                    % 🚨 只要攒够 1600 点（0.2秒），立刻播放并画图
                    if numel(rxAudioBuffer) >= 1600
                        seg = double(rxAudioBuffer(1:1600)) / 32768 * P.audioVolumeGain;
                        seg = max(min(seg, 1), -1); % 限幅防爆音
                        
                        % 1. 直接发声（会覆盖上一声，听起来像电报/断音，但绝对有声音！）
                        sound(seg, P.audioFs);
                        
                        % 2. 直接画图
                        set(hPlot, 'YData', seg);
                        title(sprintf('OK:%d', frameOK));
                        drawnow limitrate; % 强制刷新界面
                        
                        rxAudioBuffer(1:1600) = [];
                    end
                else
                    frameFail = frameFail + 1;
                end
                
                consume = s + frameLen - 1;
                if consume > 0 && consume <= numel(bitBuffer), bitBuffer(1:consume) = []; end
                frameStarts = frame_sync(bitBuffer, P);
            end
        end
    end
catch ME
    fprintf('\n接收结束: %s\n', ME.message);
end
release(rxRadio);