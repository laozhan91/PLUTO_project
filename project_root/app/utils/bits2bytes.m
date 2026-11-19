function bytes = bits2bytes(bits)
% bits2bytes.m  比特流 → 字节（MSB first）
%
% ⚠️ 优化：原实现用 'bin2dec(num2str(...))' 逐字节转换，
%          每帧 166 字节 → 166 次字符串/数值转换，硬件联调时成为瓶颈。
%          改为矩阵乘（uint8 × 权重），速度提升 ~100×。

bits = logical(bits(:).');
L = floor(numel(bits) / 8) * 8;
bits = bits(1:L);

if isempty(bits)
    bytes = uint8([]);
    return;
end

bitsMtx = reshape(bits, 8, []).';                 % N x 8
weights = uint8(2.^(7:-1:0));                     % [128 64 32 16 8 4 2 1]
bytes   = uint8(bitsMtx * double(weights).');     % N x 1
end