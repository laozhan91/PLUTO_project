function circle_test_demo()
    clear; clc; close all;
    % 如果不需要加载外部路径可以注释掉下一行
    % addpath(genpath('project_root')); 
    
    %% 参数配置
    Fs_audio = 8000;
    frameN = 160;   % 160个点 = 20ms @ 8kHz
    
    % 初始化音频设备
    adr = audioDeviceReader('SampleRate',Fs_audio,'SamplesPerFrame',frameN,'NumChannels',1);
    adw = audioDeviceWriter('SampleRate',Fs_audio);
    
    %% 生成静音包
    dummy_pcm = zeros(frameN,1,'int16');
    dummy_alaw = pcm16_to_alaw(dummy_pcm);
    dummy_bits = bytes2bits(dummy_alaw);
    silent_tx_bits = frame_builder(dummy_bits);
    
    %% 创建 UI 界面
    fig = figure('Name','数字环回语音测试 Demo','NumberTitle','off','Position',[200 200 800 600]);
    ax1 = subplot(3,1,1); title('发送端麦克风原始波形'); grid on; ylim([-1 1]); ylabel('幅度');
    ax2 = subplot(3,1,2); title('接收端恢复并播放的波形 (红线)'); grid on; ylim([-1 1]); ylabel('幅度');
    ax3 = subplot(3,1,3); title('调试: 比特流缓冲区长度与搜索状态'); grid on; 
    
    line1 = plot(ax1, nan(frameN,1), 'b');
    line2 = plot(ax2, nan(frameN,1), 'r');
    
    uicontrol('Style','text','String','空闲中 (按空格键发射)',...
        'Position',[302 556 200 30],'FontSize',14,'BackgroundColor',[0.9 0.9 0.9]);
    
    global isTxOn;
    isTxOn = false;
    set(fig,'KeyPressFcn',@keyPressCb,'KeyReleaseFcn',@keyReleaseCb);
    
    bitBuffer = logical([]);
    loopCount = 0;
    
    fprintf('=== 测试就绪，请点击图形窗口，按住空格键说话 ===\n');
    
    %% 主循环
    while ishandle(fig)
        loopCount = loopCount + 1;
        
        % 1. 采集
        if isTxOn
            frame_dbl = adr();
            frame_pcm = int16(frame_dbl * 32768);
            alaw_bytes = pcm16_to_alaw(frame_pcm);
            aLawBits = bytes2bits(alaw_bytes);
            txBits = frame_builder(aLawBits);
        else
            frame_dbl = zeros(frameN, 1);
            txBits = silent_tx_bits;
        end
        
        % 2. 物理层环回 (QPSK)
        txBits = txBits(:);
        if mod(length(txBits), 2) ~= 0; txBits = [txBits; 0]; end
        txSym = pskmod(txBits, 4, pi/4, 'InputType', 'bit');
        rxSym = txSym; 
        rxBits = pskdemod(rxSym, 4, pi/4, 'OutputType', 'bit');
        rxBits = logical(rxBits(:).'); 
        
        % 3. 寻包
        bitBuffer = [bitBuffer, rxBits];
        if length(bitBuffer) > 20000
            bitBuffer = bitBuffer(end-19999:end); 
        end
        
        audio_play = zeros(frameN, 1);
        pktValid = false;
        
        while length(bitBuffer) >= 30*8
            [pkt, isValid, consumedBits] = extract_packet(bitBuffer);
            if isValid
                bitBuffer = bitBuffer(consumedBits+1:end);
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
                bitBuffer = bitBuffer(consumedBits+1:end); 
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
            title(ax3, sprintf('缓存: %d | 找到包: %d | 播放峰值: %.2f', length(bitBuffer), pktValid, max(abs(audio_play))));
            drawnow limitrate;
        end
    end
    release(adr); release(adw);
end

%% ================= 以下为局部函数（必须与主程序在同一个文件里） =================

function keyPressCb(~,evt)
    global isTxOn;
    if strcmp(evt.Key,'space'); isTxOn = true; end
end

function keyReleaseCb(~,evt)
    global isTxOn;
    if strcmp(evt.Key,'space'); isTxOn = false; end
end

function txBits = frame_builder(aLawBits)
    header_bytes = uint8([0xAA, 0x55]);
    tail_bytes   = uint8([0x55, 0xAA]);
    aLawBytes    = bits2bytes(aLawBits);
    
    payload_len  = uint8(length(aLawBytes)); 
    crc_in = [payload_len; aLawBytes];
    crc_byte = crc8_calc(crc_in, 0x07);
    
    pkt_bytes = [header_bytes, payload_len, aLawBytes.', crc_byte, tail_bytes];
    txBits = bytes2bits(pkt_bytes);
end

function [payload, isValid, consumedBits] = extract_packet(bitBuffer)
    isValid = false; payload = uint8([]); consumedBits = 0;
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
        consumedBits = idx; 
    end
end

function bytes = bits2bytes(bits)
    L = length(bits); rem = mod(L, 8);
    if rem ~= 0; bits = bits(1 : L - rem); end
    if isempty(bits); bytes = uint8([]); return; end
    bits = reshape(bits, 8, [])';
    bytes = zeros(size(bits,1),1,'uint8');
    for i = 1:size(bits,1)
        bytes(i) = bin2dec(num2str(bits(i,:)));
    end
end

function bits = bytes2bits(bytes)
    bits = logical([]);
    for i = 1:numel(bytes)
        b = bytes(i);
        bits = [bits, bitget(b,8:-1:1)];
    end
end

function crc_out = crc8_calc(data, poly)
    crc = uint8(0);
    for i = 1:length(data)
        crc = bitxor(crc, data(i));
        for j = 1:8
            if bitand(crc, 0x80); crc = bitxor(bitshift(crc,1), poly);
            else; crc = bitshift(crc,1); end
            crc = bitand(crc, 0xFF);
        end
    end
    crc_out = crc;
end

function alaw_out = pcm16_to_alaw(pcm_in)
    alaw_out = zeros(size(pcm_in),'uint8');
    for n = 1:length(pcm_in)
        s = pcm_in(n); sign = 0;
        if s < 0; sign = 1; s = -s; end
        s = uint16(s); s = bitand(s, uint16(0x1FFF));
        if s < 32; seg = 0; q = s;
        elseif s < 64; seg = 1; q = bitshift(s,-1)-16;
        elseif s < 128; seg = 2; q = bitshift(s,-2)-16;
        elseif s < 256; seg = 3; q = bitshift(s,-3)-16;
        elseif s < 512; seg = 4; q = bitshift(s,-4)-16;
        elseif s < 1024; seg = 5; q = bitshift(s,-5)-16;
        elseif s < 2048; seg = 6; q = bitshift(s,-6)-16;
        else; seg = 7; q = bitshift(s,-7)-16; end
        code = bitor(uint8(seg)*16, uint8(q));
        if sign; code = bitor(code, uint8(0x80)); end
        code = bitxor(code, uint8(0x55));
        alaw_out(n) = code;
    end
end

function pcm_out = alaw_to_pcm16(alaw_in)
    pcm_out = zeros(size(alaw_in),'int16');
    for n = 1:length(alaw_in)
        a = bitxor(alaw_in(n), 0x55);
        sign = bitand(a,0x80); seg = bitand(bitshift(a,-4), 0x07); q = bitand(a, 0x0F);
        switch seg
            case 0; sample = q;
            case 1; sample = 16 + q*2;
            case 2; sample = 32 + q*4;
            case 3; sample = 64 + q*8;
            case 4; sample = 128 + q*16;
            case 5; sample = 256 + q*32;
            case 6; sample = 512 + q*64;
            case 7; sample = 1024 + q*128;
        end
        if sign ~= 0; sample = -sample; end
        sample = sample * 8;
        if sample > 32767; sample = 32767; end
        if sample < -32768; sample = -32768; end
        pcm_out(n) = int16(sample);
    end
end