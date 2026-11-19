% calibrate_pluto_freq.m
% 放在 scripts/ 目录下
clc; clear; close all;
addpath(genpath(fullfile(pwd, '..'))); % 添加上级路径
P = params('loopback');

fs = P.basebandRate; 
fc = P.centerFreq; 
fTone = 80e3; % 放在基带内的参考单音 80kHz

disp('正在启动 Pluto 进行频率校准...');
% 1. TX 发射参考单音
tx = sdrtx('Pluto', 'RadioID', P.radioID_tx, 'CenterFrequency', fc, ...
           'BasebandSampleRate', fs, 'Gain', P.txGain, 'FrequencyCorrection', 0);
tone = exp(1j*2*pi*fTone*(0:20000-1)'/fs);
transmitRepeat(tx, tone);

% 2. RX 接收单音
rx = sdrrx('Pluto', 'RadioID', P.radioID_rx, 'CenterFrequency', fc, ...
           'BasebandSampleRate', fs, 'SamplesPerFrame', 2^18, ...
           'OutputDataType', 'double', 'FrequencyCorrection', 0);
disp('等待接收稳定...');
rxSig = rx(); % 丢弃第一帧
for k = 1:5, rxSig = rx(); end % 多收几帧确保稳定

% 3. FFT 找峰值算频偏
Y = fftshift(abs(fft(rxSig)));
fAxis = (-length(rxSig)/2 : length(rxSig)/2-1)' * (fs/length(rxSig));
[~, idx] = max(Y); 
fReceived = fAxis(idx);

% 4. 计算 PPM
ppmToAdd = (fReceived - fTone) / (fc + fTone) * 1e6; 

% 5. 存盘
save('pluto_cal.mat', 'ppmToAdd');
fprintf('✅ 校准完成！实际单音频率: %.3f kHz\n', fReceived/1000);
fprintf('建议 RX 频偏校正值 (PPM): %.4f\n', ppmToAdd);

release(tx); release(rx);