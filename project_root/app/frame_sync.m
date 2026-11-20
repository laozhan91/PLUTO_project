function frameStarts = frame_sync(bitBuffer, P)
% frame_sync.m  在比特流里搜索所有候选帧起点
%
% 无 FEC: 搜 AA55 及其 1~7 位左/右偏移(应对采样相位不确定)
% RS 整帧: 搜 4 字节同步字 AA55AA55, 允许 P.fecSyncMaxErr 个比特错
%          (同步字在 FEC 保护之外, 严格匹配时高 BER 下丢帧几乎全由它造成)

bitBuffer = bitBuffer(:).'; 

if fec_enabled(P)
    syncBits = bytes2bits(P.fecSyncBytes);
    frameStarts = sync_search(syncBits, bitBuffer, P.fecSyncMaxErr, 16, numel(syncBits));
    return;
end

headerBits = logical(P.preambleBits(:).');

frameStarts = [];

% 搜索 AA55 以及它向左/向右偏移 1~7 位的所有可能
for shift = 0:7
    hdr = circshift(headerBits, shift);
    idx = strfind(bitBuffer, hdr);
    if ~isempty(idx)
        % 如果找到了，把起点算回去
        frameStarts = [frameStarts, idx - shift]; 
    end
end

frameStarts = unique(frameStarts);
frameStarts = frameStarts(frameStarts > 0);
end
