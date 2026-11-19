% test_loopback_cfo.m
clc; clear; close all;
addpath(genpath(pwd));

P = params('loopback');

% 1. 生成数据
payloadBytes = randi([0 255], 160, 1);
lenVal = 160;
lenBits = de2bi(lenVal, 8, 'left-msb')';
payloadBits = bytes2bits(payloadBytes); payloadBits = payloadBits(:);
crcVal = crc8_calc([uint8(lenVal); payloadBytes], uint8(0x07));
crcBits = de2bi(crcVal, 8, 'left-msb')';
tailBits = bytes2bits(uint8([0x55; 0xAA])); tailBits = tailBits(:);

frameBits = [P.preambleBits(:); lenBits(:); payloadBits(:); crcBits(:); tailBits(:)];

% 🚨 注意：这里加了 4000 个随机比特，确保包被完全包裹在中间
txBits = [randi([0 1], 4000, 1); frameBits; randi([0 1], 4000, 1)];

% 2. TX 调制
[txWaveform, ~, ~] = tx_chain(P, txBits);

% 3. 施加残酷损伤
cfo_hz = 31000; 
fs = P.basebandRate; n = (0:length(txWaveform)-1)';
txWaveform = txWaveform .* exp(1j*2*pi*cfo_hz*n/fs); 
txWaveform = txWaveform * exp(1j * 2.1); 
rxWaveform = awgn(txWaveform, 15, 'measured'); 

% 4. RX 解调
[rxBitsQuad, rxSym, metrics] = rx_chain(rxWaveform, P);
fprintf('估算的 CFO 频偏: %.1f Hz\n', metrics.cfoEst);
fprintf('接收到总符号数: %d\n', length(rxSym));

figure; plot(real(rxSym), imag(rxSym), '.'); title('完美星座图'); axis square; grid on;

% 5. 暴力解包
found = false;
for q = 1:4
    rxBits = rxBitsQuad{q}(:).'; % 强制行向量
    frameStarts = frame_sync(rxBits, P);
    
    for i = 1:length(frameStarts)
        [~, crcOK, ~] = frame_parser(rxBits, frameStarts(i), P);
        if crcOK
            fprintf('✅ 完美！找到包！CRC=0！(象限: %d, 索引: %d)\n', q, frameStarts(i));
            found = true;
            break;
        end
    end
    if found, break; end
end

if ~found
    fprintf('❌ 极度遗憾，还没找到。\n');
end