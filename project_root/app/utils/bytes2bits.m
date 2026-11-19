function bits = bytes2bits(bytes)
% bytes2bits.m  字节 → 比特流（MSB first）
%
% 用 dec2bin 向量化展开，不依赖 bitget 的隐式扩展，
% 任何 MATLAB 版本（R2014a 起）都能跑。

bytes = uint8(bytes(:));
if isempty(bytes)
    bits = logical([]);
    return;
end

str  = dec2bin(bytes, 8);            % N x 8 char，'10101010'
bits = logical(str - '0');            % N x 8 logical
bits = reshape(bits.', 1, []);        % 1 x N*8
end