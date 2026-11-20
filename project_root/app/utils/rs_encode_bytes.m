function cw = rs_encode_bytes(msg)
% rs_encode_bytes.m  RS(255,223) 编码(系统码, 每符号 1 字节)
%
% 用法:  cw = rs_encode_bytes(msg)     msg: K x 1 uint8 (K = 223)
% 输出:  cw  - 255 x 1 uint8
%
% 说明: comm.RSEncoder 建对象开销大, 用 persistent 复用; 退出前 clear rs_encode_bytes

persistent enc

K = 223;
msg = uint8(msg(:));
if numel(msg) ~= K
    error('rs_encode_bytes: 输入必须为 %d 字节(当前 %d)', K, numel(msg));
end

if isempty(enc)
    enc = comm.RSEncoder(255, K);
end
cw = uint8(enc(double(msg)));
cw = cw(:);
end
