function [msg, nerr] = rs_decode_bytes(cw)
% rs_decode_bytes.m  RS(255,223) 译码
%
% 用法:  [msg, nerr] = rs_decode_bytes(cw)    cw: 255 x 1 uint8
% 输出:  msg  - 223 x 1 uint8 (译出的信息段)
%        nerr - 纠正的符号错个数
%
% 注意: 错符号数超过 t=16 时译码器会返回"看似合法"的错误结果,
%       必须靠上层 CRC-8 兜底判定, 不能只看译码器是否报错。

persistent dec

N = 255;

cw = uint8(cw(:));
if numel(cw) ~= N
    error('rs_decode_bytes: 输入必须为 %d 字节(当前 %d)', N, numel(cw));
end

if isempty(dec)
    dec = comm.RSDecoder(255, 223);
end
[msg, nerr] = dec(double(cw));
msg = uint8(msg(:));
end
