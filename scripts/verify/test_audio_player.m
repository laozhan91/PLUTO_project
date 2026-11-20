function test_audio_player()
% test_audio_player.m  播放缓冲逻辑自检(不打开声卡, 只验证排队/去重/补丢帧)
%
% 覆盖 audio_player 的 push 路径:
%   1) 序号连续 → 队列按帧增长, 无重复/补帧
%   2) 同序号重复推入(发射端 repmat 造成) → 丢弃, 队列不再增长
%   3) 序号跳变(丢帧) → 按缺失帧数补隐藏帧
%   4) 序号回退(迟到旧帧) → 丢弃
%
% 说明: 'tick' 会真实打开声卡, 因此不在此自检覆盖。

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..', '..', 'project_root')));

P = params('overair');
P.audioFs = 8000;
P.audioVolumeGain = 3;
frameN = round(P.audioFs * P.audioFrameSec);

pcm = int16(round(3000*sin(2*pi*220*(0:frameN-1).'/P.audioFs)));
alaw = pcm16_to_alaw(pcm);

fprintf('=== 播放缓冲自检 ===\n');
audio_player('init', P);

audio_player(alaw, P, uint8(0));
audio_player(alaw, P, uint8(1));
s = audio_player('stats');
check(s.good == 2 && s.dup == 0 && s.gap == 0, '连续序号: 2 帧入队, 无重复/补帧');
check(s.queued == 2*frameN, '队列 = 2 帧样本数');

audio_player(alaw, P, uint8(1));            % 重复帧(repmat)
s = audio_player('stats');
check(s.dup == 1 && s.queued == 2*frameN, '重复帧被丢弃, 队列不变');

audio_player(alaw, P, uint8(4));            % 跳过 2、3 → 缺 2 帧
s = audio_player('stats');
check(s.gap == 2, '序号跳变识别出 2 帧丢失');
check(s.queued == 5*frameN, '补入 2 帧隐藏数据');

audio_player(alaw, P, uint8(1));            % 迟到旧帧
s = audio_player('stats');
check(s.dup == 2 && s.queued == 5*frameN, '迟到旧帧被丢弃');

audio_player('init', P);
audio_player(alaw, P);                      % 无序号(无 FEC 格式): 直接入队
s = audio_player('stats');
check(s.good == 1 && s.queued == frameN, '无序号帧正常入队');

%% 电平换算(防止 PCM 量纲被误当 ±1 而削顶)
P.audioVolumeGain = 3;
quiet = int16(round(300*sin(2*pi*220*(0:frameN-1).'/P.audioFs)));
audio_player('init', P);
audio_player(pcm16_to_alaw(quiet), P, uint8(7));
y = audio_player('pull', P, frameN);
peak = max(abs(y));
expect = 300/32768 * P.audioVolumeGain;
check(peak < 0.05 && abs(peak - expect) < 0.01, ...
    sprintf('小信号按增益放大而非削顶(峰值 %.4f, 期望 %.4f)', peak, expect));
check(max(abs(y)) < 1, '小信号未触到限幅 ±1');

% 大信号仍应被限幅保护, 不能溢出
loud = int16(30000*sin(2*pi*220*(0:frameN-1).'/P.audioFs));
audio_player('init', P);
audio_player(pcm16_to_alaw(loud), P, uint8(8));
y = audio_player('pull', P, frameN);
check(max(abs(y)) <= 1 + 1e-9, '大信号被限幅在 ±1 之内');

audio_player('release');
fprintf('=== 全部通过 ===\n');
end

function check(cond, msg)
if cond
    fprintf('  通过  %s\n', msg);
else
    error('test_audio_player: 失败 -> %s', msg);
end
end
