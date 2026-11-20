function circle_test_demo(mode)
% circle_test_demo([mode])
%   mode = 'selfcheck'  : 离线自检(默认, 无需声卡, 客观测 SNR)
%   mode = 'interactive': 声卡环回(点击图形窗口, 按住空格说话)
%                         R 键切换 无FEC / RS(255,223) 整帧协议
%                         E 键切换 信道误码注入率(0 / 0.1% / 0.5% / 1%)
    clc; close all;
    % 加载 project_root 里已修复的 A-law / 组帧工具(路径相对本文件)
    thisDir = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(thisDir, '..', '..', 'project_root')));
    
    if nargin < 1 || isempty(mode)
        mode = 'selfcheck';
    end
    if strcmp(mode, 'interactive')
        run_interactive();
    else
        run_self_check();
    end
end

function run_interactive()
    %% 参数配置
    Fs_audio = 8000;
    frameN = 160;   % 160个点 = 20ms @ 8kHz
    
    % 初始化音频设备
    adr = audioDeviceReader('SampleRate',Fs_audio,'SamplesPerFrame',frameN,'NumChannels',1);
    adw = audioDeviceWriter('SampleRate',Fs_audio);
    
    %% 预生成静音帧(两种协议各一份, 空闲/未按键时发送)
    dummy_pcm  = zeros(frameN,1,'int16');
    dummy_alaw = pcm16_to_alaw(dummy_pcm);
    silent_tx_nofec = frame_builder_nofec(bytes2bits(dummy_alaw));
    silent_tx_rs    = frame_builder_rs(dummy_alaw);
    
    %% 创建 UI 界面
    fig = figure('Name','数字环回语音测试 Demo','NumberTitle','off','Position',[200 200 800 600]);
    ax1 = subplot(3,1,1); title('发送端麦克风原始波形'); grid on; ylim([-1 1]); ylabel('幅度');
    ax2 = subplot(3,1,2); title('接收端恢复并播放的波形 (红线)'); grid on; ylim([-1 1]); ylabel('幅度');
    ax3 = subplot(3,1,3); title('调试: 比特流缓冲区长度与搜索状态'); grid on; 
    
    line1 = plot(ax1, nan(frameN,1), 'b');
    line2 = plot(ax2, nan(frameN,1), 'r');
    
    statusTxt = uicontrol('Style','text','String','空闲中 | 协议: 无FEC | 注入BER: 0%',...
        'Position',[152 556 500 30],'FontSize',12,'BackgroundColor',[0.9 0.9 0.9]);
    
    fig.UserData.isTxOn  = false;
    fig.UserData.useRS   = false;
    fig.UserData.berList = [0 0.001 0.005 0.01];   % E 键循环注入的信道误码率
    fig.UserData.berIdx  = 1;
    fig.UserData.ber     = 0;
    set(fig,'KeyPressFcn',@keyPressCb,'KeyReleaseFcn',@keyReleaseCb);
    
    bufCap = 20000;
    bitBuffer = false(1, bufCap);
    bufLen = 0;
    loopCount = 0;
    
    fprintf('=== 测试就绪: 点击图形窗口, 按住空格说话; R 切换协议, E 切换注入误码 ===\n');
    
    %% 主循环
    nGood = 0;      % 通过帧校验的帧数
    nBad  = 0;      % 搜到同步字/帧头但 CRC 或 RS 译码失败的帧数
    while ishandle(fig)
        loopCount = loopCount + 1;
        useRS = fig.UserData.useRS;
        ber   = fig.UserData.ber;
        
        % 1. 采集 + 组帧
        if fig.UserData.isTxOn
            frame_dbl  = adr();
            frame_pcm  = int16(round(frame_dbl * 32767));
            alaw_bytes = pcm16_to_alaw(frame_pcm);
            if useRS
                txBits = frame_builder_rs(alaw_bytes);
            else
                txBits = frame_builder_nofec(bytes2bits(alaw_bytes));
            end
        else
            frame_dbl = zeros(frameN, 1);
            if useRS
                txBits = silent_tx_rs;
            else
                txBits = silent_tx_nofec;
            end
        end
        
        % 2. 物理层环回 (QPSK) + 可选信道误码注入
        txBits = pad_to_even(txBits);
        txSym  = pskmod(txBits, 4, pi/4, 'InputType', 'bit');
        rxSym  = txSym;
        rxBits = pskdemod(rxSym, 4, pi/4, 'OutputType', 'bit');
        rxBits = logical(rxBits(:).'); 
        if ber > 0
            rxBits = corrupt(rxBits, ber);
        end
        
        % 3. 寻包: 追加新比特, 超出容量丢弃最旧
        nNew = numel(rxBits);
        if bufLen + nNew > bufCap
            shiftN = bufLen + nNew - bufCap;
            bitBuffer(1:bufLen-shiftN) = bitBuffer(shiftN+1:bufLen);
            bufLen = bufLen - shiftN;
        end
        bitBuffer(bufLen+1:bufLen+nNew) = rxBits;
        bufLen = bufLen + nNew;
        
        audio_play = zeros(frameN, 1);
        pktValid = false;
        if useRS
            minBits = rs_proto().minBits;   % 同步字 32bit + 码字 2040bit
        else
            minBits = 30*8;
        end
        
        while bufLen >= minBits
            [pkt, isValid, consumedBits, badFrame] = extract_any(bitBuffer(1:bufLen), useRS);
            if badFrame
                nBad = nBad + 1;
            end
            if isValid
                bitBuffer(1:bufLen-consumedBits) = bitBuffer(consumedBits+1:bufLen);
                bufLen = bufLen - consumedBits;
                nGood = nGood + 1;
                pcm_out = alaw_to_pcm16(pkt);
                if length(pcm_out) == frameN
                    % 放大音量并限幅防爆音
                    audio_play = double(pcm_out) / 32768.0 * 4; 
                    audio_play(audio_play > 1) = 1;
                    audio_play(audio_play < -1) = -1;
                    pktValid = true;
                end
                break; 
            elseif consumedBits > 0
                bitBuffer(1:bufLen-consumedBits) = bitBuffer(consumedBits+1:bufLen);
                bufLen = bufLen - consumedBits;
            else
                break; 
            end
        end
        
        % 4. 播放音频
        adw(audio_play);
        
        % 5. 图形更新 (降低刷新频率避免卡声卡)
        if mod(loopCount, 5) == 0
            set(line1, 'YData', frame_dbl);
            set(line2, 'YData', audio_play);
            if useRS
                protoStr = 'RS(255,223)';
            else
                protoStr = '无FEC';
            end
            if pktValid
                frameStr = '新帧';
            else
                frameStr = '丢帧';
            end
            title(ax3, sprintf('%s | 注入BER %.1f%% | 本帧 %s | 好帧 %d / 坏帧 %d | 缓存 %d bit | 播放峰值 %.2f', ...
                protoStr, ber*100, frameStr, nGood, nBad, bufLen, max(abs(audio_play))));
            set(statusTxt, 'String', sprintf('按住空格说话 · R 切换协议 · E 切换注入误码 | 当前 %s, BER %.1f%%', ...
                protoStr, ber*100));
            drawnow limitrate;
        end
    end
    release(adr); release(adw);
end

%% ================= 以下为局部函数（必须与主程序在同一个文件里） =================

function keyPressCb(src, evt)
    switch evt.Key
        case 'space'
            src.UserData.isTxOn = true;
        case 'r'
            src.UserData.useRS = ~src.UserData.useRS;
            if src.UserData.useRS
                fprintf('协议切换: RS(255,223) 整帧(166B 帧 + 57B 填充, 纠 16 个符号错)\n');
            else
                fprintf('协议切换: 无 FEC(原始 AA55/len/payload/CRC/55AA 帧)\n');
            end
        case 'e'
            src.UserData.berIdx = mod(src.UserData.berIdx, numel(src.UserData.berList)) + 1;
            src.UserData.ber    = src.UserData.berList(src.UserData.berIdx);
            fprintf('信道误码注入: %.1f%%\n', src.UserData.ber*100);
    end
end

function keyReleaseCb(src, evt)
    if strcmp(evt.Key,'space'); src.UserData.isTxOn = false; end
end

function b = pad_to_even(b)
% 保证比特数为偶数(QPSK bit 输入要求)
    b = b(:);
    if mod(numel(b), 2) ~= 0; b = [b; false]; end
end

function txBits = frame_builder_nofec(aLawBits)
% 无 FEC 帧: [AA55][len][payload][CRC-8][55AA]
    header_bytes = uint8([0xAA, 0x55]);
    tail_bytes   = uint8([0x55, 0xAA]);
    aLawBytes    = bits2bytes(aLawBits);
    
    payload_len  = uint8(length(aLawBytes)); 
    crc_in = [payload_len; aLawBytes];
    crc_byte = crc8_calc(crc_in, 0x07);
    
    pkt_bytes = [header_bytes, payload_len, aLawBytes.', crc_byte, tail_bytes];
    txBits = bytes2bits(pkt_bytes);
end

function [payload, isValid, consumedBits, badFrame] = extract_packet_nofec(bitBuffer)
    isValid = false; payload = uint8([]); consumedBits = 0; badFrame = false;
    header_bits = bytes2bits(uint8([0xAA, 0x55]));
    
    idx = strfind(bitBuffer, header_bits);
    if isempty(idx); return; end
    idx = idx(1);
    
    if length(bitBuffer) < idx + 16 + 8; return; end
    lenByte = bin2dec(num2str(bitBuffer(idx+16 : idx+23)));
    
    data_bits_len = (lenByte + 2) * 8;
    
    if length(bitBuffer) < idx + 16 + data_bits_len - 1
        return; 
    end
    
    pktBits = bitBuffer(idx+16 : idx+16+data_bits_len-1);
    pktBytes = bits2bytes(pktBits);
    
    payload = pktBytes(2:end-1);
    crcRx   = pktBytes(end);
    crcCalc = crc8_calc([lenByte; payload], 0x07);
    
    total_bits = 16 + data_bits_len + 16; 

    if crcCalc == crcRx
        isValid = true;
        consumedBits = idx + total_bits - 1; 
    else
        badFrame = true;
        consumedBits = idx; 
    end
end

%% ==================== RS(255,223) 整帧协议 ====================
% 物理帧: [同步字 AA 55 AA 55 = 32bit][RS(255,223) 码字 = 255B]
%   同步字不受 RS 保护, 必须容错匹配(见 find_sync, 容 2 bit 错);
%   实测若严格匹配, 高 BER 下丢帧几乎全由同步字被打坏造成, 与 FEC 无关
% 逻辑帧: [AA55][len][payload 160B][CRC-8][55AA] = 166B, 再补 57B 零到 223B
%   帧头/长度/CRC/帧尾全部落在 RS 保护范围内, RS 纠不动的残余错误由 CRC-8 兜底丢弃
% 码字按 15x17 块交织后发送; 单码字内交织只是符号重排, 不改变可纠错个数,
%   真正抗长突发要靠跨码字深度交织(落主链路时再定)
function p = rs_proto()
    p.N  = 255;
    p.K  = 223;
    p.t  = (p.N - p.K) / 2;               % 可纠 16 个符号错
    p.frameBytes = 2 + 1 + 160 + 1 + 2;   % 166
    p.padBytes   = p.K - p.frameBytes;    % 57
    p.syncBytes  = uint8([0xAA; 0x55; 0xAA; 0x55]);
    p.syncBits   = bytes2bits(p.syncBytes);
    p.syncBits   = p.syncBits(:).';
    p.hSync      = numel(p.syncBytes) * 8;    % 32
    p.syncMaxErr = 2;                         % 同步字容 2 bit 错(见 find_sync)
    p.ilvR       = 15;
    p.ilvC       = 17;
    p.totalBits  = p.hSync + p.N*8;           % 2072, 偶数便于 QPSK 成形
    p.minBits    = p.totalBits;
end

function enc = rs_encoder()
    persistent e
    if isempty(e)
        e = comm.RSEncoder(255, 223);
    end
    enc = e;
end

function dec = rs_decoder()
    persistent d
    if isempty(d)
        d = comm.RSDecoder(255, 223);
    end
    dec = d;
end

function release_rs_codec()
    release(rs_encoder());
    release(rs_decoder());
end

function msg = build_rs_message(payloadBytes)
% 166B 逻辑帧 + 57B 零填充 = 223B RS 信息段
    p = rs_proto();
    payloadBytes = uint8(payloadBytes(:));
    lenByte = uint8(numel(payloadBytes));
    crcByte = crc8_calc([lenByte; payloadBytes], uint8(0x07));
    frame   = [uint8([0xAA;0x55]); lenByte; payloadBytes; crcByte; uint8([0x55;0xAA])];
    msg     = [frame; zeros(p.K - numel(frame), 1, 'uint8')];
end

function txBits = frame_builder_rs(payloadBytes)
    p   = rs_proto();
    enc = rs_encoder();
    msg = build_rs_message(payloadBytes);
    cw  = uint8(enc(double(msg)));
    cw  = rs_interleave(cw, p);
    txBits = bytes2bits([p.syncBytes; cw]);
    txBits = txBits(:).';
end

function [payload, isValid, consumedBits, badFrame] = extract_packet_rs(bitBuffer)
    p = rs_proto();
    isValid = false; payload = uint8([]); consumedBits = 0; badFrame = false;

    bitBuffer = bitBuffer(:).';
    idx = find_sync(p.syncBits, bitBuffer, p.syncMaxErr);
    if isempty(idx); return; end
    if idx > 1                      % 同步字之前的碎片直接丢弃
        consumedBits = idx - 1;
        return;
    end
    if numel(bitBuffer) < p.totalBits; return; end   % 等更多比特

    cwRx = bits2bytes(bitBuffer(p.hSync+1 : p.totalBits));
    cwRx = rs_deinterleave(cwRx, p);

    dec = rs_decoder();
    msg = uint8(dec(double(cwRx)));
    msg = msg(:);

    lenVal  = double(msg(3));
    okFrame = false;
    if lenVal >= 1 && 4 + lenVal + 2 <= p.frameBytes
        pl    = msg(4 : 3+lenVal);
        crcRx = msg(4 + lenVal);
        tail  = msg(5+lenVal : 6+lenVal);
        okFrame = msg(1) == uint8(0xAA) && msg(2) == uint8(0x55) && ...
                  isequal(tail, uint8([0x55; 0xAA])) && ...
                  crc8_calc([msg(3); pl], uint8(0x07)) == crcRx;
    end

    if okFrame
        isValid      = true;
        payload      = pl;
        consumedBits = p.totalBits;
    else
        badFrame     = true;
        consumedBits = p.hSync;      % 丢掉同步字重新搜索
    end
end

function idx = find_sync(syncBits, bits, maxErr)
% 允许 maxErr 位错的同步字搜索(滑窗相关), 返回第一个匹配的起始位置
%   maxErr = 0 时等价于 strfind; 32bit 同步字容 2 错时误检概率约 1e-7/位置
    n = numel(syncBits);
    idx = [];
    if numel(bits) < n || n == 0; return; end
    s = 2*double(syncBits(:).') - 1;
    x = 2*double(bits(:).')    - 1;
    c = filter(s(end:-1:1), 1, x);      % c(k) = 以 k 结尾窗口与同步字的相关值
    c = c(n:end);                        % 对齐到窗口起始位置
    hit = find(c >= n - 2*maxErr, 1);
    if ~isempty(hit)
        idx = hit;
    end
end

function out = rs_interleave(cw, p)
    W   = reshape(cw(:), p.ilvR, p.ilvC).';
    out = W(:);
end

function cw = rs_deinterleave(out, p)
    W  = reshape(out(:), p.ilvC, p.ilvR);
    cw = reshape(W.', [], 1);
end

function [pkt, isValid, consumedBits, badFrame] = extract_any(bitBuffer, useRS)
    if useRS
        [pkt, isValid, consumedBits, badFrame] = extract_packet_rs(bitBuffer);
    else
        [pkt, isValid, consumedBits, badFrame] = extract_packet_nofec(bitBuffer);
    end
end

function run_self_check()
% 离线自检(无需声卡/射频):
%   Part1 编解码正确性(0 误码 SNR)
%   Part2 丢帧隐藏策略对比(静音 / 保持 / 保持+淡出 / 交叉淡化)
%   Part3 FEC 抗误码(无FEC / (7,4)汉明 / RS(255,223), 真实编解码蒙特卡洛)
%   Part4 RS 整帧协议(组帧→RS→交织→误码→解交织→RS→CRC 全链路)
    Fs = 8000; N = 160;

    %% Part 1: 单帧 0 误码 SNR
    t = (0:N-1).'/Fs;
    env = 0.5 + 0.5*sin(2*pi*0.5*t + 0.3);
    speech = env .* (0.4*sin(2*pi*180*t) + 0.25*sin(2*pi*360*t) + 0.15*sin(2*pi*720*t));
    pcm = int16(round(speech / max(abs(speech)) * 9800));
    alaw = pcm16_to_alaw(pcm);
    txBits = frame_builder_nofec(bytes2bits(alaw));
    [pkt, ~, ~, ~] = extract_packet_nofec(ideal_demod(txBits));
    snr0 = snr_db(pcm, alaw_to_pcm16(pkt));
    fprintf('=== 离线自检 ===\n');
    fprintf('Part1  A-law 编解码(0 误码): SNR = %.1f dB\n\n', snr0);

    %% Part 2: 多帧语音 + 丢帧隐藏
    nFrames = 50;
    tt = (0:N*nFrames-1).'/Fs;
    ph = cumsum(2*pi*(170 + 20*sin(2*pi*0.3*tt)) / Fs);
    e  = 0.3 + 0.7*(0.5 + 0.5*sin(2*pi*0.4*tt));
    speechAll = e .* (0.5*sin(ph) + 0.25*sin(2*ph) + 0.12*sin(3*ph));
    pcmAll = int16(round(speechAll / max(abs(speechAll)) * 9800));
    pcmAll = reshape(pcmAll, N, nFrames);

    fprintf('Part2  丢帧隐藏(段信噪比 dB, 20 次随机丢帧平均):\n');
    fprintf('  丢帧率  [静音 | 保持 | 保持+淡出 | 交叉淡化]\n');
    for perase = [0.02 0.05 0.1 0.2]
        acc = zeros(1,4);
        for tr = 1:20
            erase = rand(1, nFrames) < perase;
            [r0,r1,r2,r3] = conceal_all(pcmAll, erase);
            acc = acc + [segsnr(pcmAll,r0), segsnr(pcmAll,r1), ...
                         segsnr(pcmAll,r2), segsnr(pcmAll,r3)];
        end
        acc = acc / 20;
        fprintf('  %2.0f%%     %6.1f | %6.1f | %6.1f | %6.1f\n', perase*100, acc);
    end

    %% Part 3: FEC 抗误码(真实编解码蒙特卡洛)
    fec_experiment(pcm);

    %% Part 4: RS 整帧协议全链路
    rs_protocol_experiment(pcm);
    release_rs_codec();
end

function [r0,r1,r2,r3] = conceal_all(pcmAll, erase)
% 四种丢帧隐藏策略
    [N, nF] = size(pcmAll);
    r0 = zeros(N,nF,'int16'); r1 = zeros(N,nF,'int16');
    r2 = zeros(N,nF,'int16'); r3 = zeros(N,nF,'int16');
    last = zeros(N,1,'int16');
    cons = 0;
    for i = 1:nF
        if ~erase(i)
            r0(:,i)=pcmAll(:,i); r1(:,i)=pcmAll(:,i);
            r2(:,i)=pcmAll(:,i); r3(:,i)=pcmAll(:,i);
            last = pcmAll(:,i); cons = 0;
        else
            r0(:,i)=0;                    % 静音(当前行为)
            r1(:,i)=last;                 % 保持上一帧
            cons = cons + 1;
            r2(:,i)=int16(double(last)*(0.7^cons));  % 保持 + 逐帧淡出
            r3(:,i)=r2(:,i);              % 先同 r2, 后面做交叉淡化
        end
    end
    % r3: 交叉淡化(用下一好帧, 离线理想上界)
    inRun = false; runStart = 1;
    for i = 1:nF
        if erase(i) && ~inRun
            inRun = true; runStart = i;
        elseif ~erase(i) && inRun
            inRun = false;
            runEnd = i - 1;
            prev = runStart - 1; next = i;
            if prev >= 1 && next <= nF
                L = runEnd - runStart + 1;
                wout = linspace(1,0,L+2); wout = wout(2:end-1);
                win  = linspace(0,1,L+2); win  = win(2:end-1);
                for k = 1:L
                    j = runStart + k - 1;
                    r3(:,j) = int16(double(pcmAll(:,prev))*wout(k) + ...
                                    double(pcmAll(:,next))*win(k));
                end
            end
        end
    end
end

function s = segsnr(ref, est)
% 段信噪比: 逐帧 SNR(dB) 平均, 跳过静音帧, 单帧上限 60 dB
    [~, nF] = size(ref);
    dbs = zeros(1, nF);
    cnt = 0;
    for i = 1:nF
        r = double(ref(:,i)); e = double(est(:,i));
        vr = var(r);
        if vr >= 1e-3
            ve = var(r - e);
            d = 10*log10(vr / max(ve, 1e-6));
            cnt = cnt + 1;
            dbs(cnt) = min(d, 60);
        end
    end
    s = mean(dbs(1:cnt));
end

function fec_experiment(pcm)
% Part3: 真实 FEC 编解码蒙特卡洛, 统计丢帧率
    payload = pcm16_to_alaw(pcm);                 % 160 字节 A-law
    rsEnc = comm.RSEncoder(255,223);
    rsDec = comm.RSDecoder(255,223);
    fprintf('\nPart3  FEC 抗误码(真实编解码, 300 次蒙特卡洛):\n');
    fprintf('  BER     无FEC丢帧%%   (7,4)汉明丢帧%%   RS(255,223)丢帧%%\n');
    for ber = [0.001 0.002 0.005 0.01 0.02]
        rn = fec_trials(payload, ber, 'none',  rsEnc, rsDec);
        rh = fec_trials(payload, ber, 'hamming', rsEnc, rsDec);
        rr = fec_trials(payload, ber, 'rs', rsEnc, rsDec);
        fprintf('  %5.3f     %6.1f%%       %6.1f%%         %6.1f%%\n', ...
            ber, rn*100, rh*100, rr*100);
    end
    release(rsEnc); release(rsDec);
end

function drop = fec_trials(payload, ber, mode, rsEnc, rsDec)
    T = 300; drops = 0;
    len = uint8(numel(payload));
    crc = crc8_calc([len; payload], 0x07);
    for tr = 1:T
        ok = false;
        switch mode
            case 'none'
                bits = corrupt(bytes2bits([payload; crc]), ber);
                b = bits2bytes(bits);
                ok = (numel(b) >= numel(payload)+1) && ...
                     (crc8_calc([len; b(1:numel(payload))], 0x07) == b(numel(payload)+1));
            case 'hamming'
                bits = hamming_encode_bytes([payload; crc]);
                bits = interleave_bits(bits);
                bits = corrupt(bits, ber);
                bits = deinterleave_bits(bits);
                b = hamming_decode_bytes(bits);
                ok = (numel(b) >= numel(payload)+1) && ...
                     (crc8_calc([len; b(1:numel(payload))], 0x07) == b(numel(payload)+1));
            case 'rs'
                rsIn = [payload; crc; zeros(62,1,'uint8')];
                rsEncB = uint8(rsEnc(double(rsIn(:))));
                rsRx = bits2bytes(corrupt(bytes2bits(rsEncB), ber));
                if numel(rsRx) == 255
                    rsDecB = uint8(rsDec(double(rsRx(:))));
                    ok = (numel(rsDecB) >= numel(payload)+1) && ...
                         (crc8_calc([len; rsDecB(1:numel(payload))], 0x07) == rsDecB(numel(payload)+1));
                end
        end
        if ~ok; drops = drops + 1; end
    end
    drop = drops / T;
end

function bits = corrupt(bits, ber)
    bits = logical(bits(:).');
    flip = rand(size(bits)) < ber;
    bits(flip) = ~bits(flip);
end

function bits = hamming_encode_bytes(bytes)
    b = bytes2bits(bytes);
    if mod(length(b),4) ~= 0; b = [b, false(1, 4-mod(length(b),4))]; end
    nib = reshape(b, 4, []);
    nCw = size(nib,2);
    cw = false(7, nCw);
    for k = 1:nCw
        cw(:,k) = hamming74_encode(nib(:,k).');
    end
    bits = reshape(cw, 1, []);
end

function bytes = hamming_decode_bytes(bits)
    bits = logical(bits(:).');
    L = floor(length(bits)/7)*7;
    cw = reshape(bits(1:L), 7, []);
    nCw = size(cw,2);
    nib = false(4, nCw);
    for k = 1:nCw
        nib(:,k) = hamming74_decode(cw(:,k).');
    end
    bytes = bits2bytes(reshape(nib, 1, []));
end

function cw = hamming74_encode(nib)
% (7,4)系统汉明码: [d1 d2 d3 d4 p1 p2 p3]
    d = double(nib(:).');
    p = mod([d(1)+d(2)+d(4); d(1)+d(3)+d(4); d(2)+d(3)+d(4)], 2);
    cw = logical([d, p.']);
end

function d = hamming74_decode(cw)
% 纠 1 位错; 返回 4 位数据
    c = double(cw(:).');
    s1 = mod(c(1)+c(2)+c(4)+c(5), 2);
    s2 = mod(c(1)+c(3)+c(4)+c(6), 2);
    s3 = mod(c(2)+c(3)+c(4)+c(7), 2);
    sVal = s1*1 + s2*2 + s3*4;
    if sVal > 0
        posTable = [0 5 6 1 7 2 3 4];
        pos = posTable(sVal + 1);
        c(pos) = mod(c(pos) + 1, 2);
    end
    d = logical(c(1:4));
end

function out = interleave_bits(bits)
% 块交织: 每行一个码字写入, 按列读出, 把突发错打散
    bits = bits(:).'; n = numel(bits);
    R = 7; C = n / R;
    W = reshape(bits, R, C).';
    out = W(:).';
end

function out = deinterleave_bits(bits)
    bits = bits(:).'; n = numel(bits);
    R = 7; C = n / R;
    W = reshape(bits, C, R);
    out = reshape(W.', 1, []);
end

function rxBits = ideal_demod(txBits)
% 理想 QPSK 调制/解调,不引入误码(用于纯环回)
    b = txBits;
    if mod(length(b), 2) ~= 0; b = [b, 0]; end
    sym = pskmod(b(:), 4, pi/4, 'InputType', 'bit');
    rxBits = logical(pskdemod(sym, 4, pi/4, 'OutputType', 'bit'));
    rxBits = rxBits(:).';
end

function s = snr_db(ref, est)
% 用方差比计算的 SNR(ref 与 est 尺寸一致, int16/double 均可)
    ref = double(ref(:)); est = double(est(:));
    s = 10*log10(var(ref) / max(var(ref - est), 1e-12));
end

%% ==================== Part4: RS 整帧协议实验 ====================
function rs_protocol_experiment(pcm)
% 与将来落地主链路一致的全链路: 组帧 → RS(255,223) → 交织 → (注入误码)
%                                  → 解交织 → RS 译码 → CRC 校验 → 解帧
    p   = rs_proto();
    ref = pcm16_to_alaw(pcm(:));

    fprintf('\nPart4  RS 整帧协议(逻辑帧 %dB + %dB 零填充 = %dB → RS(%d,%d), t=%d)\n', ...
        p.frameBytes, p.padBytes, p.K, p.N, p.K, p.t);
    fprintf('  物理帧 = [同步字 AA55AA55 32bit(容 2bit 错)][码字 %dB = %dbit], 共 %d bit; 交织 %dx%d\n', ...
        p.N, p.N*8, p.totalBits, p.ilvR, p.ilvC);

    txNo = frame_builder_nofec(bytes2bits(ref));
    txRs = frame_builder_rs(ref);

    % 4a 0 误码往返
    [pkt, ok] = extract_packet_rs(txRs);
    if ok && isequal(pkt, ref)
        fprintf('  4a 0 误码往返: 通过(payload 160 字节完全一致)\n');
    elseif ok
        fprintf('  4a 0 误码往返: 失败(payload 不一致)\n');
    else
        fprintf('  4a 0 误码往返: 失败(帧头/长度/CRC/帧尾校验未过)\n');
    end
    cw0 = uint8((0:p.N-1).');
    if isequal(rs_deinterleave(rs_interleave(cw0, p), p), cw0)
        fprintf('     交织可逆性: 通过\n');
    else
        fprintf('     交织可逆性: 失败\n');
    end

    % 4b 误码扫描
    T = 200;
    fprintf('  4b 误码扫描(%d 次/点): 丢帧 = 该帧未被正确解出\n', T);
    fprintf('     BER    协议    同步/帧头失配%%   FEC/CRC失败%%   总丢帧%%    SNR(dB)  通道符号错/帧\n');
    for ber = [0 0.001 0.002 0.005 0.01 0.02]
        [s1, f1, snr1]        = frame_trials(txNo, ref, pcm, ber, T, false);
        [s2, f2, snr2, neSym] = frame_trials(txRs, ref, pcm, ber, T, true);
        fprintf('     %5.3f   无FEC  %13.1f%%   %11.1f%%   %7.1f%%   %8.1f         -\n', ...
            ber, s1*100, f1*100, (s1+f1)*100, snr1);
        fprintf('             RS     %13.1f%%   %11.1f%%   %7.1f%%   %8.1f   %8.1f\n', ...
            s2*100, f2*100, (s2+f2)*100, snr2, neSym);
    end

    % 4c 突发错误
    fprintf('  4c 突发错误(距帧头 40%% 处注入连续 L 比特错):\n');
    fprintf('     L(bit)   无FEC    RS(255,223)\n');
    for L = [8 32 64 100 128 200 400]
        fprintf('     %4d     %4s      %6s\n', L, ...
            pf(burst_ok(txNo, ref, L, false)), pf(burst_ok(txRs, ref, L, true)));
    end

    % 4d 流式缓冲自检(与交互模式同一套缓冲区/寻包逻辑)
    [nDec, nExp, okStream] = stream_check();
    if okStream
        fprintf('  4d 流式缓冲自检: 通过(从半帧开始接收, 后续 %d 帧全部正确解出)\n', nDec);
    else
        fprintf('  4d 流式缓冲自检: 失败(正确解出 %d 帧, 期望 %d 帧)\n', nDec, nExp);
    end
end

function [nDec, nExp, okAll] = stream_check()
% 模拟 run_interactive 的比特缓冲区 + 寻包循环, 验证流式接收(含起始半帧)
    frameN = 160; nFrames = 12;
    pcmSeq = int16(round(3000*sin(2*pi*220*(0:frameN*nFrames-1).'/8000)));
    pcmSeq = reshape(pcmSeq, frameN, nFrames);

    allBits = false(1, nFrames * rs_proto().totalBits);
    for k = 1:nFrames
        b = frame_builder_rs(pcm16_to_alaw(pcmSeq(:,k)));
        allBits((k-1)*numel(b)+1 : k*numel(b)) = b;
    end
    allBits = allBits(138:end);            % 模拟从半帧开始接收, 首帧必然作废

    bufCap = 6000;
    bitBuffer = false(1, bufCap); bufLen = 0;
    minBits = rs_proto().minBits;
    nDec = 0; okAll = true; pos = 1;
    nExp = nFrames - 1;

    while pos <= numel(allBits)
        nNew  = min(minBits, numel(allBits) - pos + 1);
        chunk = allBits(pos : pos+nNew-1);
        pos   = pos + nNew;

        if bufLen + nNew > bufCap
            shiftN = bufLen + nNew - bufCap;
            bitBuffer(1:bufLen-shiftN) = bitBuffer(shiftN+1:bufLen);
            bufLen = bufLen - shiftN;
        end
        bitBuffer(bufLen+1:bufLen+nNew) = chunk;
        bufLen = bufLen + nNew;

        while bufLen >= minBits
            [pkt, isValid, consumedBits] = extract_any(bitBuffer(1:bufLen), true);
            if isValid
                nDec  = nDec + 1;
                % 首帧被切掉, 第 n 个解出的帧对应发送端第 n+1 帧
                okAll = okAll && nDec <= nExp && ...
                        isequal(pkt, pcm16_to_alaw(pcmSeq(:, nDec+1)));
                bitBuffer(1:bufLen-consumedBits) = bitBuffer(consumedBits+1:bufLen);
                bufLen = bufLen - consumedBits;
            elseif consumedBits > 0
                bitBuffer(1:bufLen-consumedBits) = bitBuffer(consumedBits+1:bufLen);
                bufLen = bufLen - consumedBits;
            else
                break;
            end
        end
    end
    okAll = okAll && (nDec == nExp);
end

function [syncLoss, fecFail, snrMean, symErrMean] = frame_trials(txBits, ref, pcm, ber, T, useRS)
% 单协议整帧蒙特卡洛: 同步/帧头失配率 + FEC/CRC 失败率 + 成功帧端到端 SNR
    p = rs_proto();
    syncLoss = 0; fecFail = 0; snrAcc = 0; nGood = 0; symAcc = 0;
    snrMean = NaN; symErrMean = NaN;
    if useRS
        enc  = rs_encoder();
        cwTx = uint8(enc(double(build_rs_message(ref))));
    end
    for tr = 1:T
        rxBits = corrupt(txBits, ber);
        if useRS
            [pkt, ok, ~, bad] = extract_packet_rs(rxBits);
            cwRx = rs_deinterleave(bits2bytes(rxBits(p.hSync+1 : p.totalBits)), p);
            symAcc = symAcc + sum(cwRx ~= cwTx);
        else
            [pkt, ok, ~, bad] = extract_packet_nofec(rxBits);
        end
        if ok
            snrAcc = snrAcc + min(snr_db(pcm, alaw_to_pcm16(pkt)), 60);
            nGood  = nGood + 1;
        elseif bad
            fecFail = fecFail + 1;
        else
            syncLoss = syncLoss + 1;
        end
    end
    syncLoss = syncLoss / T;
    fecFail  = fecFail / T;
    if nGood > 0
        snrMean = snrAcc / nGood;
    end
    if useRS
        symErrMean = symAcc / T;
    end
end

function ok = burst_ok(txBits, ref, L, useRS)
    b  = logical(txBits(:).');
    st = round(0.4 * numel(b));
    st = min(max(st, 1), numel(b) - L + 1);
    b(st : st+L-1) = ~b(st : st+L-1);
    if useRS
        [pkt, ok] = extract_packet_rs(b);
    else
        [pkt, ok] = extract_packet_nofec(b);
    end
    ok = ok && isequal(pkt, ref);
end

function s = pf(ok)
    if ok
        s = '通过';
    else
        s = '失败';
    end
end