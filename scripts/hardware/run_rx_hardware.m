%% run_rx_hardware.m (终极整合版)
clear; clc; close all;
addpath(genpath('project_root'));
warning('off', 'comm:SymbolSynchronizer:SymbolDropping'); 

P = params('overair');
P.basebandRate    = 250e3;  
% 🚨 修复 1：必须抓足够多的点，一帧需要 2656 点，8192 点能装下 3 帧！
P.rxFrameLength   = 8192;    
P.rxGain          = 60;     

% 🚨 修复 2：如果之前没跑过 calibrate_pluto_freq.m，P.rxPPMCorrection 默认是 0
if ~isfield(P, 'rxPPMCorrection')
    P.rxPPMCorrection = 0;
end

try, release(sdrrx('Pluto')); catch, end
pause(1);

% 🚨 修复 3：加入 FrequencyCorrection
rxRadio = sdrrx('Pluto', ...
    'CenterFrequency', P.centerFreq, ...
    'BasebandSampleRate', P.basebandRate, ...
    'SamplesPerFrame', P.rxFrameLength, ...
    'OutputDataType', 'double', ...
    'GainSource', 'Manual', ...
    'Gain', P.rxGain, ...
    'FrequencyCorrection', P.rxPPMCorrection); % 注入 PPM 校准

% 🚨 修复 4：初始化 4 个比特缓冲区，对应 4 个象限
bitBuffer = cell(1, 4);
for q = 1:4, bitBuffer{q} = []; end

played_count = 0;
iter = 0;

fprintf('=== RX 硬件启动！等待接收真实信号... ===\n');
fprintf('当前 PPM 校准值: %.3f\n', P.rxPPMCorrection);

try
    while true
        iter = iter + 1;
        
        % 1. 抓取 IQ 数据
        try, [rxWave, ~, ~] = rxRadio(); catch, continue; end
        if max(abs(rxWave)) < 1e-6, continue; end
        
        % 2. 直接调用我们纯软件验证过的无敌 rx_chain！
        % 返回的 rxBitsQuad 是一个包含 4 个象限比特流元胞数组
        [rxBitsQuad, rxSym, metrics] = rx_chain(rxWave, P);
        
        % 3. 遍历 4 个象限解包
        for q = 1:4
            % 拼接到对应的缓冲区
            bitBuffer{q} = [bitBuffer{q}, rxBitsQuad{q}(:).'];
            
            % 防溢出保护（保留最后 10000 bit）
            if numel(bitBuffer{q}) > 20000
                bitBuffer{q} = bitBuffer{q}(end - 9999 : end);
            end
            
            % 找包头
            frameStarts = frame_sync(bitBuffer{q}, P);
            
            % 循环解包
            parse_limit = 5; % 每次最多解 5 个包，防止卡顿
            while ~isempty(frameStarts) && parse_limit > 0
                parse_limit = parse_limit - 1;
                s = frameStarts(1);
                [payloadBytes, crcOK, frameLen] = frame_parser(bitBuffer{q}, s, P);
                
                if frameLen == 0, break; end
                
                % 严格校验，发真包
                if crcOK && numel(payloadBytes) == 160
                    pcm = alaw_to_pcm16(payloadBytes);
                    sound(double(pcm)/32768 * 3, P.audioFs);
                    played_count = played_count + 1;
                    fprintf('✅ 捕获真包！🔊 播放第 %d 帧 (象限: %d, 估算CFO: %.0fHz)\n', ...
                        played_count, q, metrics.cfoEst);
                    
                    % 成功播放后，清空对应缓冲区之前的无效数据
                    consume = s + frameLen - 1;
                    bitBuffer{q}(1:consume) = [];
                else
                    % 如果没解出来，丢弃这一个候选帧头，继续往后搜
                    bitBuffer{q}(1:s) = []; 
                end
                
                % 重新在剩余的 buffer 里找
                frameStarts = frame_sync(bitBuffer{q}, P);
            end
        end
        
        % 打印一下射频最大值，监控天线状态
        if mod(iter, 100) == 0
            fprintf('监控: max(|rxWave|) = %.3f\n', max(abs(rxWave)));
        end
    end
catch ME
    fprintf('\n接收结束: %s\n', ME.message);
end
release(rxRadio);