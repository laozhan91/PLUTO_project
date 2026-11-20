function [payloadBytes, crcOK, frameLen, seqByte] = frame_parser(bitBuffer, startIdx, P)
% frame_parser.m  从候选起点解析一个帧
%
% 用法:  [payloadBytes, crcOK, frameLen, seqByte] = frame_parser(bitBuffer, startIdx, P)
% 输出:
%   payloadBytes - A-law 字节列向量(失败时为空)
%   crcOK        - 帧头/长度/CRC/帧尾全部通过
%   frameLen     - 整帧比特数; 0 表示"数据还不够, 等下一轮"; 1 表示"该起点无效, 丢弃"
%   seqByte      - 帧序号(仅 RS 整帧格式有, 无 FEC 时为空)
%
% frameLen 的三种取值是调用方(帧同步循环)的契约, 不要改语义。

crcOK        = false;
payloadBytes = uint8([]);
frameLen     = 1;
seqByte      = [];

if fec_enabled(P)
    [payloadBytes, crcOK, frameLen, seqByte] = parse_fec(bitBuffer, startIdx, P);
    return;
end

HDR_BITS = 16; LEN_BITS = 8; CRC_BITS = 8; TAIL_BITS = 16;

if numel(bitBuffer) < startIdx + HDR_BITS + LEN_BITS - 1
    frameLen = 0; return;
end

lenStart = startIdx + HDR_BITS;
lenBits  = bitBuffer(lenStart : lenStart + LEN_BITS - 1);
lenVal   = sum(lenBits .* (2.^(LEN_BITS-1:-1:0)));

% 强制校验：长度 160
if lenVal ~= 160
    return; 
end

frameTotalBits = HDR_BITS + LEN_BITS + lenVal*8 + CRC_BITS + TAIL_BITS;
if numel(bitBuffer) < startIdx + frameTotalBits - 1
    frameLen = 0; return;
end

payloadStart = lenStart + LEN_BITS;
payloadEnd   = payloadStart + lenVal*8 - 1;
payloadBytes = bits2bytes(bitBuffer(payloadStart : payloadEnd));

crcStart = payloadEnd + 1;
crcBits  = bitBuffer(crcStart : crcStart + CRC_BITS - 1);
crcRx    = uint8(sum(crcBits .* (2.^(CRC_BITS-1:-1:0))));

tailStart = crcStart + CRC_BITS;
tailBytes = bits2bytes(bitBuffer(tailStart : tailStart + 15));

if ~isequal(tailBytes, uint8([0x55; 0xAA]))
    return;
end

crcCalc = crc8_calc([uint8(lenVal); payloadBytes], uint8(0x07));
if crcCalc == crcRx
    crcOK    = true;
    frameLen = frameTotalBits;
end
end

function [payloadBytes, crcOK, frameLen, seqByte] = parse_fec(bitBuffer, startIdx, P)
% RS 整帧解析: 同步字(容错) → 取 255B 码字 → RS 译码 → 长度/CRC/帧尾校验
crcOK        = false;
payloadBytes = uint8([]);
frameLen     = 1;
seqByte      = [];

syncBits = bytes2bits(P.fecSyncBytes);
syncBits = syncBits(:).';
hSync    = numel(syncBits);
totalBits = hSync + P.fecN*8;

if startIdx < 1 || numel(bitBuffer) < startIdx + hSync - 1
    frameLen = 0; return;
end

seg = bitBuffer(startIdx : startIdx + hSync - 1);
if sum(seg(:).' ~= syncBits) > P.fecSyncMaxErr
    return;                     % 不是同步字, frameLen=1: 丢弃该候选起点
end

if numel(bitBuffer) < startIdx + totalBits - 1
    frameLen = 0; return;       % 码字还没收全
end

cwBits = bitBuffer(startIdx + hSync : startIdx + totalBits - 1);
msg    = rs_decode_bytes(bits2bytes(cwBits));

if numel(msg) < 7
    return;
end
lenVal = double(msg(3));
if lenVal < 1 || 7 + lenVal > numel(msg)
    return;
end

pl    = msg(5 : 4+lenVal);
crcRx = msg(5 + lenVal);
tail  = msg(6+lenVal : 7+lenVal);
legal = msg(1) == uint8(0xAA) && msg(2) == uint8(0x55) && ...
        isequal(tail, uint8([0x55; 0xAA])) && ...
        crc8_calc([msg(3); msg(4); pl], uint8(0x07)) == crcRx;

if legal
    crcOK        = true;
    payloadBytes = pl;
    seqByte      = msg(4);
    frameLen     = totalBits;
end
end
