function crc_out = crc8_calc(data, poly)
% crc8_calc.m  CRC-8（poly 可配，默认 0x07）
%
% ⚠️ 优化：
%   原实现未强制 uint8，如果 poly 传 double（如 '0x07'），
%   内部 crc 变量会被隐式提升成 double，虽然逻辑正确但类型不确定，
%   在不同上下文（如与 uint8 比较）可能踩隐式转换坑。
%   这里全程 uint8，彻底类型确定。

if nargin < 2 || isempty(poly)
    poly = uint8(0x07);
end
poly = uint8(poly);
data = uint8(data(:));

crc = uint8(0);
for i = 1:numel(data)
    crc = bitxor(crc, data(i));
    for j = 1:8
        if bitand(crc, uint8(0x80))
            crc = bitxor(bitshift(crc, 1), poly);
        else
            crc = bitshift(crc, 1);
        end
        crc = bitand(crc, uint8(0xFF));
    end
end
crc_out = crc;
end