function txBits = frame_builder(pcm_frame, P)
% frame_builder.m  PCM 帧 → A-law → 组帧 → txBits
%
% 两种格式, 由 P.enableFEC 决定(收/发必须一致):
%   无 FEC: [Header AA55][Length][Payload][CRC-8][Tail 55AA]              1328 bit
%   RS 整帧: [同步字 AA55AA55][RS(255,223) 码字]                           2072 bit
%            逻辑帧 [AA55][Length][Seq][Payload][CRC-8][55AA], 补零到 223B
%
% CRC-8: poly=0x07, init=0, 无 FEC 时覆盖 [Length, Payload];
%        RS 整帧时覆盖 [Length, Seq, Payload] (帧头/帧尾另由 RS 保护)
%
% 用法:  txBits = frame_builder(pcm_frame, P)
%        frame_builder('reset')      % 复位帧序号计数器(每次开始发射前调用)
% 输入:  pcm_frame - int16 列向量
% 输出:  txBits    - logical 行向量

persistent seqCounter
if isempty(seqCounter)
    seqCounter = 0;
end

if ischar(pcm_frame)
    if strcmpi(pcm_frame, 'reset')
        seqCounter = 0;
        txBits = logical([]);
        return;
    end
    error('frame_builder: 未知命令 %s', pcm_frame);
end

alawBytes = pcm16_to_alaw(pcm_frame);       % uint8 列向量

lenVal = numel(alawBytes);
if lenVal > 255
    error('frame_builder: payload %d bytes > 255（超 8-bit Length 上限）', lenVal);
end
lenByte = uint8(lenVal);

headerBytes = uint8([0xAA; 0x55]);
tailBytes   = uint8([0x55; 0xAA]);

if ~fec_enabled(P)
    crcByte  = crc8_calc([lenByte; alawBytes], uint8(0x07));
    pktBytes = [headerBytes; lenByte; alawBytes; crcByte; tailBytes];
    txBits   = bytes2bits(pktBytes);
    txBits   = txBits(:).';
    return;
end

% ---- RS 整帧：序号 → CRC → 补零 → RS 编码 → 拼同步字 ----
seqByte    = uint8(seqCounter);
seqCounter = mod(seqCounter + 1, 256);

crcByte = crc8_calc([lenByte; seqByte; alawBytes], uint8(0x07));
frame   = [headerBytes; lenByte; seqByte; alawBytes; crcByte; tailBytes];
msg     = [frame; zeros(P.fecK - numel(frame), 1, 'uint8')];

cw     = rs_encode_bytes(msg);
txBits = bytes2bits([P.fecSyncBytes; cw]);
txBits = txBits(:).';
end
