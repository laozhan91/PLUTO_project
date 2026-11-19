function alaw_out = pcm16_to_alaw(pcm_in)
% pcm16_to_alaw.m  int16 PCM → A-law 8-bit（ITU G.711）
%
% [修复 1] 补上 16-bit → 13-bit 的 /8 缩放（原代码漏掉导致大信号全饱和）
% [修复 2] seg=0 时 q = floor(s/2)（原代码 q=s 会让 4-bit q 溢出）
% [修复 3] 用 double 内部计算，避免 int16(-32768) 取负溢出

alaw_out = zeros(size(pcm_in), 'uint8');

for n = 1:numel(pcm_in)
    s    = double(pcm_in(n));
    sign = 0;
    if s < 0
        sign = 1;
        s = -s;
    end

    % ---- 16-bit → 13-bit（右移 3 位 + 饱和到 4095）----
    s = floor(s / 8);
    if s > 4095, s = 4095; end

    % ---- G.711 分段量化（8 段 × 16 级）----
    if     s < 32,   seg = 0; q = floor(s / 2);
    elseif s < 64,   seg = 1; q = floor(s / 2)  - 16;
    elseif s < 128,  seg = 2; q = floor(s / 4)  - 16;
    elseif s < 256,  seg = 3; q = floor(s / 8)  - 16;
    elseif s < 512,  seg = 4; q = floor(s / 16) - 16;
    elseif s < 1024, seg = 5; q = floor(s / 32) - 16;
    elseif s < 2048, seg = 6; q = floor(s / 64) - 16;
    else,            seg = 7; q = floor(s / 128) - 16;
    end

    code = uint8(seg) * 16 + uint8(q);
    if sign
        code = bitor(code, uint8(0x80));
    end
    code = bitxor(code, uint8(0x55));
    alaw_out(n) = code;
end
end