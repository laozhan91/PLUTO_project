function y = audio_proc_rx(x, P)
% audio_proc_rx.m  接收端音频后处理: 只做高通(去直流 / 低频嗡声)
%
% 用法:
%   audio_proc_rx('reset', P)   复位内部状态
%   y = audio_proc_rx(x, P)     处理一帧 PCM(±32768 量纲), 返回同量纲 double
%
% 为什么只做高通:
%   底噪已经在发射端用噪声门压掉了。收端再串一级门/谱减容易伤语音
%   (谱减还会引入音乐噪声, 并需要重叠相加与额外延迟), 收益不抵风险。
%
% 状态跨帧保留(zi), 否则帧边界会出现跳变咔哒声。

persistent b1 a1 b2 a2 fs zi1 zi2

y = [];
if ischar(x)
    if strcmpi(x, 'reset')
        b1 = []; a1 = []; b2 = []; a2 = []; fs = []; zi1 = []; zi2 = [];
        return;
    end
    error('audio_proc_rx: 未知命令 %s', x);
end

x = double(x(:));
if isempty(x)
    y = x;
    return;
end

if isempty(fs) || fs ~= P.audioFs
    fs = P.audioFs;
    fc = 90;
    if isfield(P, 'procHpHz') && ~isempty(P.procHpHz)
        fc = P.procHpHz;
    end
    [b1, a1] = hp_biquad(fc, fs, 0.5412);
    [b2, a2] = hp_biquad(fc, fs, 1.3066);
    zi1 = zeros(2,1);  zi2 = zeros(2,1);
end

[hp, zi1] = filter(b1, a1, x, zi1);
[hp, zi2] = filter(b2, a2, hp, zi2);
y = max(min(hp, 32767), -32768);
end
