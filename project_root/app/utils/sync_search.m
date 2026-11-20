function hits = sync_search(syncBits, bits, maxErr, maxHits, minGap)
% sync_search.m  允许 maxErr 位错的同步字搜索(滑窗相关)
%
% 用法:  hits = sync_search(syncBits, bits, maxErr, maxHits, minGap)
%   syncBits - logical 行/列向量, 同步字
%   bits     - logical 行/列向量, 待搜索比特流
%   maxErr   - 允许的比特错个数, 0 等价于 strfind
%   maxHits  - 最多返回多少个起点(默认 16), 防止误检刷屏
%   minGap   - 相邻命中点最小间距(默认 1); 取同步字长度可去掉重叠命中
% 输出:  hits - 1 x M, 同步字在 bits 中的起始下标(1 基)
%
% 为什么不用 strfind: 同步字不在 FEC 保护范围内, 严格匹配时只要同步字被打坏
%   任何一个 bit 整帧就丢, 高 BER 下丢帧几乎全由同步字造成(实测 BER=0.5% 时
%   15.5% 的丢帧全部来自同步字)。容 2bit 错后这部分消失。
%
% 为什么需要 minGap: 帧头也是 AA55, 紧跟在同步字 AA55AA55 之后, 因此同步字后移
%   16bit 的窗口仍是 AA55AA55 —— 会产生一个重叠的假命中。按同步字长度去重即可。

if nargin < 3 || isempty(maxErr),  maxErr  = 0;  end
if nargin < 4 || isempty(maxHits), maxHits = 16; end
if nargin < 5 || isempty(minGap),  minGap  = 1;  end

hits = [];
bits = logical(bits(:).');
syncBits = logical(syncBits(:).');
n = numel(syncBits);
if n == 0 || numel(bits) < n
    return;
end
if maxErr <= 0
    hits = strfind(bits, syncBits);
else
    s = 2*double(syncBits) - 1;
    x = 2*double(bits)     - 1;
    c = filter(s(end:-1:1), 1, x);      % c(k): 以 k 结尾的窗口与同步字的相关值
    c = c(n:end);                        % 对齐到窗口起始位置
    hits = find(c >= n - 2*maxErr);
end

if minGap > 1 && ~isempty(hits)
    keep = hits(1);
    for k = 2:numel(hits)
        if hits(k) - keep(end) >= minGap
            keep(end+1) = hits(k); %#ok<AGROW>
        end
    end
    hits = keep;
end

if numel(hits) > maxHits
    hits = hits(1:maxHits);
end
end
