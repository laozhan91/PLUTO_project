%% run_tx_hardware.m (一直持续发射版本，去掉空格PTT)
clear; clc; close all;
addpath(genpath('project_root'));
P = params('overair');
P.basebandRate = 250e3;
P.txGain = 0;
P.audioFs = 8000;
P.enableFEC = true;         % RS 整帧协议; ⚠️ 必须与接收端 run_rx_hardware.m 一致
frame_builder('reset');     % 复位帧序号计数器, 每次开始发射都从 0 开始

% 1. 初始化硬件
fprintf('正在初始化 Pluto...\n');
tx = sdrtx('Pluto', 'RadioID', P.radioID_tx, 'CenterFrequency', P.centerFreq, 'BasebandSampleRate', P.basebandRate, 'Gain', P.txGain);
txFilt = comm.RaisedCosineTransmitFilter('RolloffFactor', P.rolloff, 'FilterSpanInSymbols', P.span, 'OutputSamplesPerSymbol', P.sps, 'Shape', 'Square root');

% 2. audioDeviceReader 配置
BLOCK_SEC = 0.02;
CHUNK_N = round(P.audioFs * BLOCK_SEC);    % 1600 采样点
BLOCK_SAMPLES = round(P.basebandRate * BLOCK_SEC); % 50000 点
frameN = round(P.audioFs * 0.02);          % 20ms = 160点

fprintf('正在初始化麦克风...\n');
adr = audioDeviceReader('SampleRate', P.audioFs, 'SamplesPerFrame', CHUNK_N, 'NumChannels', 1);

% ================== UI界面 ==================
fig = figure('Name','持续发射端','NumberTitle','off','Position',[400 400 600 400], 'MenuBar', 'none');
ui_txt = uicontrol('Style','text','String','🎤 持续采集发射中...','Position',[50 330 500 50],...
    'FontSize',14,'BackgroundColor',[0.6 1 0.6], 'ForegroundColor','k','FontWeight','bold');
hAx = axes('Position', [0.1 0.1 0.8 0.6]); hold(hAx,'on'); grid(hAx,'on');
hLine = plot(hAx, zeros(1, CHUNK_N), 'b');
ylim(hAx, [-1 1]); xlim(hAx, [1 CHUNK_N]);
title(hAx, '麦克风输入波形');
xlabel(hAx, '采样点'); ylabel(hAx, '幅度 (已放大5倍)');
drawnow;

fprintf('=== 就绪！持续采集麦克风并发射，关闭窗口停止 ===\n\n');

% ================== 主循环：永远采集+发射 ==================
loopCnt = 0;
while ishandle(fig)
    loopCnt = loopCnt + 1;
    
    % 阻塞读取200ms麦克风音频
    chunk_dbl = adr();
    nextBits = [];
    for k = 1:(CHUNK_N/frameN)
        f_pcm = chunk_dbl((k-1)*frameN+1 : k*frameN);
        b = frame_builder(int16(f_pcm * 32767), P);
        b = b(:);
        if mod(numel(b), P.bps)~=0
            b = [b; false(P.bps-mod(numel(b),P.bps),1)];
        end
        nextBits = [nextBits; b];
    end

    % 调制+成型滤波
        % 调制+成型滤波
    w = txFilt(pskmod(nextBits, P.M, pi/4, 'InputType', 'bit'));
    w_rep = repmat(w, ceil(BLOCK_SAMPLES / length(w)), 1); % 关键修改：用循环复制代替补零
    txWave = w_rep(1:BLOCK_SAMPLES) / max(abs(w_rep)) * 0.7;

    % 送Pluto发射
    tx(txWave);

    % 打印TX HEX（前32字节）
    bit2byte = reshape(nextBits(1:floor(numel(nextBits)/8)*8),8,[])';
    byteVal = uint8(bi2de(bit2byte,'left-msb'));
    fprintf('TX HEX: '); fprintf('%02X ',byteVal(1:min(32,end))); fprintf('\n');

    % 更新波形图
    maxAmp = max(abs(chunk_dbl));
    set(fig, 'Name', '持续发射端 [🎤 发射语音中]');
    set(ui_txt, 'String', sprintf('🎤 正在发射... (麦克风峰值: %.4f)', maxAmp));
    set(hLine, 'YData', chunk_dbl * 5);

    if mod(loopCnt, 5) == 0
        drawnow limitrate;
    end
end

release(tx); release(txFilt); release(adr);
disp('发射结束');