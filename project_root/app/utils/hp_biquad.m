function [b, a] = hp_biquad(fc, fs, Q)
% hp_biquad.m  二阶高通 biquad 系数(RBJ Audio EQ Cookbook)
%
% 用法:  [b, a] = hp_biquad(fc, fs, Q)
% 说明:
%   - 不依赖 Signal Processing Toolbox 的 butter(), 系数按解析式直接算出
%   - a(1) 已归一化为 1, 可直接用于 [y, zi] = filter(b, a, x, zi)
%   - 级联两个不同 Q 的 biquad 即得 4 阶 Butterworth:
%       Q = 0.5412 与 Q = 1.3066
%     90Hz / 8kHz 时: 50Hz 约 -20dB(压电源嗡声), 100Hz 约 -1.5dB(不动语音基频)

w0    = 2*pi*fc/fs;
cw    = cos(w0);
sw    = sin(w0);
alpha = sw / (2*Q);

b0 = (1 + cw) / 2;
b1 = -(1 + cw);
b2 = (1 + cw) / 2;
a0 = 1 + alpha;
a1 = -2*cw;
a2 = 1 - alpha;

b = [b0, b1, b2] / a0;
a = [1, a1/a0, a2/a0];
end
