function ber = measure_ber(rxBits, txBits, P)
% measure_ber.m  带互相关对齐的 BER 计算
%
% ✅ 改动点：
%   1) 去掉硬编码 skipBits=400 —— rx_chain 已按 P.warmupSymbols 截断过，
%      这里再硬丢 400 位会让对齐窗口偏移、缩小有效比特数。
%      若某些场景需要额外丢弃，显式设置 P.berSkipBits 即可（默认 0）。
%   2) xcorr 搜索窗从固定 500 扩到 min(numel, P.maxBerLag)，默认 2000，
%      兼容更长帧；同时三种对齐分支都加了越界保护。
%   3) 入参强制行向量、空/全零等退化情况直接返回 0.5，避免下游 NaN。

rxBits = rxBits(:).';
txBits = txBits(:).';

if isempty(rxBits) || isempty(txBits) || ~any(rxBits)
    ber = 0.5;
    return;
end

% ---- 1. 可选：额外跳过预热位（仅当显式设置 P.berSkipBits 时生效） ----
if isfield(P,'berSkipBits') && P.berSkipBits > 0
    sk = min(P.berSkipBits, numel(rxBits)-1);
    rxBits = rxBits(sk+1:end);
end

% ---- 2. 互相关对齐 ----
x = 2*rxBits - 1;
y = 2*txBits - 1;

if isfield(P,'maxBerLag') && P.maxBerLag > 0
    maxLag = min(max(numel(rxBits), numel(txBits)), P.maxBerLag);
else
    maxLag = min(max(numel(rxBits), numel(txBits)), 2000);
end

[c, lags] = xcorr(x, y, maxLag);
[~, max_idx] = max(abs(c));
best_lag = lags(max_idx);

% ---- 3. 按最佳延迟对齐（带越界保护） ----
if best_lag > 0
    rStart = best_lag + 1;
    rEnd   = min(numel(rxBits), best_lag + numel(txBits));
    r = rxBits(rStart : rEnd);
    t = txBits(1 : numel(r));
elseif best_lag < 0
    tStart = -best_lag + 1;
    tEnd   = min(numel(txBits), -best_lag + numel(rxBits));
    t = txBits(tStart : tEnd);
    r = rxBits(1 : numel(t));
else
    n = min(numel(rxBits), numel(txBits));
    r = rxBits(1:n);
    t = txBits(1:n);
end

if isempty(r)
    ber = 0.5;
    return;
end

% ---- 4. BER ----
err = sum(r ~= t);
ber = err / numel(r);
end