function test_fec_protocol()
% test_fec_protocol.m  主项目帧协议端到端自检(无需声卡/射频)
%
% 覆盖 frame_builder / frame_sync / frame_parser 在两种 P.enableFEC 下的行为:
%   1) 无 FEC 往返: payload 一致, 且不返回序号(回归保护)
%   2) RS 整帧往返: payload 一致, 序号逐帧递增
%   3) 误码下 RS 明显优于无 FEC
%   4) 丢帧时序号跳变可被识别(播放端据此补隐藏帧)
%
% 用法:  test_fec_protocol        (在 scripts/verify 目录下, 或 addpath 后调用)

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..', '..', 'project_root')));

P = params('overair');
P.audioFs = 8000;
frameN = round(P.audioFs * P.audioFrameSec);

pcm = int16(round(3000*sin(2*pi*220*(0:frameN-1).'/P.audioFs)));
ref = pcm16_to_alaw(pcm);

fprintf('=== 帧协议自检 ===\n');

%% 1) 无 FEC 往返(回归)
P.enableFEC = false;
txBits  = frame_builder(pcm, P);
starts  = frame_sync(txBits, P);
[pkt, ok, flen, seq] = frame_parser(txBits, starts(1), P);
check(numel(txBits) == 1328, '无 FEC 帧长 1328 bit');
check(ok && isequal(pkt, ref), '无 FEC 往返 payload 一致');
check(isempty(seq), '无 FEC 不返回序号');
check(flen == 1328, '无 FEC 返回整帧长度');

%% 2) RS 整帧往返
P.enableFEC = true;
frame_builder('reset');
txBits = frame_builder(pcm, P);
check(numel(txBits) == P.fecFrameBits, sprintf('RS 帧长 %d bit', P.fecFrameBits));

starts = frame_sync(txBits, P);
check(isscalar(starts) && starts(1) == 1, '同步字定位到帧头');
[pkt, ok, flen, seq] = frame_parser(txBits, starts(1), P);
check(ok && isequal(pkt, ref), 'RS 往返 payload 一致');
check(double(seq) == 0, '首帧序号为 0');
check(flen == P.fecFrameBits, 'RS 返回整帧长度');

t2 = frame_builder(pcm, P);
[~, ok2, ~, seq2] = frame_parser(t2, 1, P);
check(ok2 && double(seq2) == 1, '序号逐帧递增');

%% 3) 误码下 RS vs 无 FEC
P.enableFEC = false;  txNo = frame_builder(pcm, P);
P.enableFEC = true;   frame_builder('reset'); txRs = frame_builder(pcm, P);

T = 200; ber = 0.002;
okNo = 0; okRs = 0;
for k = 1:T
    b = corrupt(txNo, ber);
    s = frame_sync(b, setfield(P, 'enableFEC', false)); %#ok<SFLD>
    okNo = okNo + decode_ok(b, s, setfield(P, 'enableFEC', false)); %#ok<SFLD>
    b = corrupt(txRs, ber);
    s = frame_sync(b, P);
    okRs = okRs + decode_ok(b, s, P);
end
fprintf('  BER %.1f%%: 无 FEC 成功率 %.1f%% | RS 成功率 %.1f%%\n', ber*100, okNo/T*100, okRs/T*100);
check(okRs/T > 0.9, 'BER 0.2% 时 RS 成功率 > 90%');

%% 4) 丢帧导致序号跳变
P.enableFEC = true;
frame_builder('reset');
f = cell(1, 6);
for k = 1:6, f{k} = frame_builder(pcm, P); end
stream = [f{1}, f{2}, f{4}, f{5}];        % 丢掉 seq=2 的那一帧
seqs = [];
buf = stream;
while true
    s = frame_sync(buf, P);
    if isempty(s), break; end
    [~, ok, flen, sq] = frame_parser(buf, s(1), P);
    if flen == 0, break; end
    if ok
        seqs(end+1) = double(sq);          %#ok<AGROW>
        buf(1 : s(1)+flen-1) = [];
    else
        buf(1 : s(1)) = [];
    end
end
check(isequal(seqs, [0 1 3 4]), '丢 1 帧后序号序列为 0,1,3,4');

clear rs_encode_bytes rs_decode_bytes frame_builder
fprintf('=== 全部通过 ===\n');
end

%% ---------- 局部函数 ----------
function ok = decode_ok(bits, starts, P)
ok = false;
if isempty(starts), return; end
[~, good, flen] = frame_parser(bits, starts(1), P);
if flen > 0
    ok = good;
end
end

function check(cond, msg)
if cond
    fprintf('  通过  %s\n', msg);
else
    error('test_fec_protocol: 失败 -> %s', msg);
end
end

function bits = corrupt(bits, ber)
bits = logical(bits(:).');
flip = rand(size(bits)) < ber;
bits(flip) = ~bits(flip);
end
