clear; clc;
addpath(genpath('project_root'));
P = params('overair');

% 1. 生成一段 1kHz 的“滴——”声
P.audioFs = 8000;
t = (0:159)' / P.audioFs;
pcm_in = int16(sin(2*pi*1000*t) * 10000); 

% 2. TX: 组帧 -> 调制
b = frame_builder(pcm_in, P);
b = b(:); 
if mod(numel(b), P.bps)~=0, b = [b; false(P.bps-mod(numel(b),P.bps),1)]; end
txSym = pskmod(b, P.M, pi/4, 'InputType', 'bit');

% 3. 信道（纯理想）
rxSym = txSym;
rxBits = pskdemod(rxSym, P.M, pi/4, 'OutputType', 'bit');
rxBits = rxBits(:).';

% 4. RX: 解包
frameStarts = frame_sync(rxBits, P);
fprintf('找到包头数量: %d\n', numel(frameStarts));

if ~isempty(frameStarts)
    s = frameStarts(1);
    [payloadBytes, crcOK, frameLen] = frame_parser(rxBits, s, P);
    fprintf('CRC 校验结果: %d\n', crcOK);
    fprintf('解析出的前 8 个字节: %s\n', num2str(payloadBytes(1:8)', '%02X '));
    
    % 5. 播放
    pcm_out = alaw_to_pcm16(payloadBytes);
    fprintf('准备播放 1kHz 纯音...\n');
    sound(double(pcm_out)/32768, P.audioFs);
end