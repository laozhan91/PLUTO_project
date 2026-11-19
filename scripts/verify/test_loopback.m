% test_loopback.m
clc; clear; close all;
addpath(genpath(pwd));

P = params('loopback');

% 1. 生成数据 (模拟 160 字节的 payload = 1280 bits)
payloadBytes = randi([0 255], 160, 1);
lenVal = 160;

% 统一生成列向量
lenBits = de2bi(lenVal, 8, 'left-msb')';
payloadBits = bytes2bits(payloadBytes);
payloadBits = payloadBits(:); % 强制列向量

% 计算 CRC
crcVal = crc8_calc([uint8(lenVal); payloadBytes], uint8(0x07));
crcBits = de2bi(crcVal, 8, 'left-msb')';

% 帧尾
tailBits = bytes2bits(uint8([0x55; 0xAA]));
tailBits = tailBits(:);

% 🚨 组帧：全部强制展平为列向量拼接
frameBits = [P.preambleBits(:); lenBits(:); payloadBits(:); crcBits(:); tailBits(:)];

% 为了防滤波器延迟，前后补点随机比特
txBits = [randi([0 1], 200, 1); frameBits; randi([0 1], 200, 1)];

fprintf('生成的一帧总比特数: %d\n', length(frameBits));

% 2. TX 调制与成型
[txWaveform, ~, ~] = tx_chain(P, txBits);

% 3. 🚨 模拟硬件信道损伤
% 加入 180 度相位旋转 (QPSK 模糊)
txWaveform = txWaveform * exp(1j * pi); 
% 加入大频偏 (模拟 Pluto 每次上电的 3kHz 偏差)
fs = P.basebandRate; n = (0:length(txWaveform)-1)';
txWaveform = txWaveform .* exp(1j*2*pi*3000*n/fs);
% 加入噪声
rxWaveform = awgn(txWaveform, 15, 'measured');

% 4. RX 解调
[rxBits, rxSym, metrics] = rx_chain(rxWaveform, P, txBits);
fprintf('物理层 BER = %.3e\n', metrics.ber);

figure; 
plot(real(rxSym), imag(rxSym), '.'); 
title('接收星座图 (相位已补偿)'); axis square; grid on;

% 5. 帧同步与解析
rxBits = rxBits(:); % 确保是列向量
[frameStarts, phaseStates] = frame_sync(rxBits, P);
fprintf('发现 %d 个候选帧头\n', length(frameStarts));

found = false;
for i = 1:length(frameStarts)
    [payloadOut, crcOK, ~] = frame_parser(rxBits, frameStarts(i), phaseStates(i), P);
    if crcOK
        fprintf('✅ 找到包！CRC=0！(位于索引 %d, 相位纠正状态: %d)\n', frameStarts(i), phaseStates(i));
        found = true;
        break;
    end
end

if ~found
    fprintf('❌ 解包失败，请检查参数或同步逻辑。\n');
end