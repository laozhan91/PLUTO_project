function frameStarts = frame_sync(bitBuffer, P)
% frame_sync.m 暴力搜索 AA55 及其所有可能的 1 比特移位
bitBuffer = bitBuffer(:).'; 

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