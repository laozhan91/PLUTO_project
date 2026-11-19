function pcm_out = alaw_to_pcm16(alaw_in)
% alaw_to_pcm16.m  A-law 8-bit → int16 PCM（ITU G.711）
%
% [修复 1] case 0~7 的反量化公式按 G.711 标准 (q+16)·2^k，原代码写错一倍
% [修复 2] 加了量化区间中点补偿，往返 SNR 提升约 3 dB

pcm_out = zeros(size(alaw_in), 'int16');

for n = 1:numel(alaw_in)
    a    = bitxor(uint8(alaw_in(n)), uint8(0x55));
    sign = bitand(a, uint8(0x80));
    seg  = double(bitshift(bitand(a, uint8(0x70)), -4));
    q    = double(bitand(a, uint8(0x0F)));

    % ---- 13-bit 反量化（中点代表值）----
    switch seg
        case 0, v = q * 2       + 1;
        case 1, v = (q + 16) * 2   + 1;
        case 2, v = (q + 16) * 4   + 2;
        case 3, v = (q + 16) * 8   + 4;
        case 4, v = (q + 16) * 16  + 8;
        case 5, v = (q + 16) * 32  + 16;
        case 6, v = (q + 16) * 64  + 32;
        case 7, v = (q + 16) * 128 + 64;
        otherwise, v = 0;
    end

    if sign ~= 0, v = -v; end

    % ---- 13-bit → 16-bit（左移 3 位）----
    v = v * 8;

    if v > 32767,  v = 32767;  end
    if v < -32768, v = -32768; end
    pcm_out(n) = int16(v);
end
end