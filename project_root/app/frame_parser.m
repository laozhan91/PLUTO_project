function [payloadBytes, crcOK, frameLen] = frame_parser(bitBuffer, startIdx, P)
% frame_parser.m 干净的解析器
crcOK = false;
payloadBytes = uint8([]);
frameLen = 1;

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