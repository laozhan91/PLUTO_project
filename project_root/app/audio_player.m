function audio_player(payloadBytes, P)
% audio_player.m  A-law 字节 → PCM → 声卡播放
%
% 用法:  audio_player(payloadBytes, P)
% 输入:  payloadBytes - uint8 列向量（A-law）
% 说明:
%   - 内部 persistent 管理 audioDeviceWriter
%   - 退出清缓存: clear audio_player
%   - 音量补偿: P.audioVolumeGain（默认 4，与环回一致；削顶时改 2）

persistent adw adwFs

if ~isfield(P,'audioVolumeGain') || isempty(P.audioVolumeGain)
    P.audioVolumeGain = 4;
end

pcm_out = alaw_to_pcm16(payloadBytes);      % int16 列向量

audio_play = double(pcm_out) / 32768.0 * P.audioVolumeGain;
audio_play = max(min(audio_play, 1), -1);   % 限幅

if isempty(adw) || adwFs ~= P.audioFs
    if ~isempty(adw), try, release(adw); catch, end, end
    adw = audioDeviceWriter('SampleRate', P.audioFs);
    adwFs = P.audioFs;
end

adw(audio_play);
end