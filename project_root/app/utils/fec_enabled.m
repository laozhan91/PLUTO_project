function tf = fec_enabled(P)
% fec_enabled.m  该次运行是否启用 RS 整帧协议(P.enableFEC)
%
% 用途: 让 frame_builder / frame_sync / frame_parser 三处对协议的选择保持一致,
%       避免各函数各写一份判断而漏改。

tf = isfield(P, 'enableFEC') && ~isempty(P.enableFEC) && logical(P.enableFEC);
end
