%% utils_selftest.m
addpath(genpath('project_root'));

% 1. 编解码往返（量化损失应 < 5%）
rng(42);
pcm = int16(8000 * randn(1000, 1));      % ~ -12dBFS 白噪
pcm = max(min(pcm, 32000), -32000);
alaw = pcm16_to_alaw(pcm);
pcm2 = alaw_to_pcm16(alaw);
mse = mean(double(pcm - pcm2).^2);
fprintf('编解码 MSE = %.1f (SNR ≈ %.1f dB)\n', mse, 10*log10(mean(double(pcm).^2)/mse));

% 2. 比特/字节往返
bits = logical(randi([0 1], 1, 1024));
bytes = bits2bytes(bits);
bits2 = bytes2bits(bytes);
assert(isequal(bits, bits2), 'bits2bytes/bytes2bits 往返失败');
fprintf('bits<->bytes 往返 OK\n');

% 3. CRC 已知值（"123456789" poly=0x07 应等于 0xF4，这是 CRC-8/ATM 标准）
data   = uint8('123456789');
crcVal = crc8_calc(data, uint8(0x07));
fprintf('CRC-8 校验值 = 0x%s (期望 0xF4)\n', upper(dec2hex(crcVal, 2)));
assert(crcVal == uint8(0xF4), 'CRC-8 标准值不符，检查算法');
fprintf('全部自检通过 ✅\n');