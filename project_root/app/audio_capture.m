function pcm_frame = audio_capture(P)
% audio_capture.m  麦克风采集一帧 16-bit PCM
%
% 用法:  pcm_frame = audio_capture(P)
% 输出:  pcm_frame - int16 列向量，长度 = round(P.audioFs * P.audioFrameSec)
%
% 说明:
%   - 内部 persistent 管理 audioDeviceReader，首次调用自动创建
%   - 退出清缓存: clear audio_capture
%   - 参数: P.audioFs (Hz), P.audioFrameSec (s)

persistent adr adrFrameN adrFs

frameN = round(P.audioFs * P.audioFrameSec);

if isempty(adr) || adrFrameN ~= frameN || adrFs ~= P.audioFs
    if ~isempty(adr), try, release(adr); catch, end, end
    adr = audioDeviceReader( ...
        'SampleRate',      P.audioFs, ...
        'SamplesPerFrame', frameN, ...
        'NumChannels',     1);
    adrFrameN = frameN;
    adrFs     = P.audioFs;
end

frame_dbl = adr();                          % [-1,1] double 列向量
frame_dbl = max(min(frame_dbl, 1), -1);     % 声卡溢出保护
pcm_frame = int16(round(frame_dbl * 32767));
end