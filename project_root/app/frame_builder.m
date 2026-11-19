function txBits = frame_builder(pcm_frame, P)
% frame_builder.m  PCM 帧 → A-law → 组帧 → txBits
%
% 帧格式（与环回测试一致）:
%   [Header 16bit AA55][Length 8bit][Payload len*8bit][CRC-8 8bit][Tail 16bit 55AA]
%   CRC-8: poly=0x07, init=0, 覆盖 [Length, Payload]（不含 Header/Tail）
%
% 用法:  txBits = frame_builder(pcm_frame, P)
% 输入:  pcm_frame - int16 列向量
% 输出:  txBits    - logical 行向量

alawBytes = pcm16_to_alaw(pcm_frame);       % uint8 列向量

lenVal = numel(alawBytes);
if lenVal > 255
    error('frame_builder: payload %d bytes > 255（超 8-bit Length 上限）', lenVal);
end
lenByte = uint8(lenVal);

crcByte = crc8_calc([lenByte; alawBytes], uint8(0x07));

headerBytes = uint8([0xAA; 0x55]);
tailBytes   = uint8([0x55; 0xAA]);
pktBytes = [headerBytes; lenByte; alawBytes; crcByte; tailBytes];

txBits = bytes2bits(pktBytes);
txBits = txBits(:).';
end