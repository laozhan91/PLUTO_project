function test_audio_proc()
% test_audio_proc.m  步骤 D 音频前/后处理自检(无需声卡/硬件)
%
% 逐级隔离验证, 每级只放开自己要测的那部分:
%   1) 高通: 去直流 + 语音基频不被削
%   2) 噪声门: 纯底噪被压低, 语音不被误伤
%   3) 慢速 AGC: 轻/响语音都收敛到目标电平
%   4) 预热期一直在讲话时, 门限不会被抬到语音电平(不能把语音切掉)
%   5) 静音段不被 AGC 提起
%   6) 帧边界连续性(状态跨帧保留)
%   7) 接收端高通
%
% 用法:  test_audio_proc

thisDir = fileparts(mfilename('fullpath'));
addpath(genpath(fullfile(thisDir, '..', '..', 'project_root')));

P = params('overair');
P.audioFs = 8000;
N     = round(P.audioFs * P.audioFrameSec);
nWarm = P.procNoiseWarmFrames;

% 三套"只放开一级"的参数
Pa = P;                                   % 只测高通
Pa.procAgcMinDb = 0;  Pa.procAgcMaxDb = 0;
Pa.procGateFloorDb = 0;

Pg = P;                                   % 测噪声门(AGC 不动)
Pg.procAgcMinDb = 0;  Pg.procAgcMaxDb = 0;

Pb = P;                                   % 测 AGC(门常开)
Pb.procGateFloorDb = 0;
Pb.procNoiseWarmFrames = 1;

fprintf('=== 音频前/后处理自检 ===\n');

%% 1) 高通
audio_proc_tx('reset', Pa);
nF = 60;
y  = run_tx(8000*ones(N*nF,1), Pa, N);
tailDc = mean(double(y(end-3*N:end)));
check(abs(tailDc) < 200, sprintf('高通去掉直流(残余均值 %.0f LSB)', tailDc));

audio_proc_tx('reset', Pa);
s300 = 8000*sin(2*pi*300*(0:N*nF-1).'/P.audioFs);
y    = run_tx(s300, Pa, N);
rIn  = rms16(round(s300(end-10*N:end)));
rOut = rms16(y(end-10*N:end));
check(rOut > 0.95*rIn, sprintf('高通不削 300Hz 语音(保留 %.0f%%)', rOut/rIn*100));

%% 2) 噪声门
rng(7);
audio_proc_tx('reset', Pg);
noise = 60*randn(N*nF,1);                     % 约 -55 dBFS
y     = run_tx(noise, Pg, N);
att   = 20*log10(rms16(y(end-10*N:end)) / rms16(round(noise(end-10*N:end))));
check(att < -15, sprintf('纯底噪被压低 %.1f dB', att));

audio_proc_tx('reset', Pg);
speech = 2000*sin(2*pi*300*(0:N*nF-1).'/P.audioFs);   % 约 -27 dBFS
y = run_tx(speech, Pg, N);
gSp = 20*log10(rms16(y(end-10*N:end)) / rms16(round(speech(end-10*N:end))));
check(gSp > -3, sprintf('门开着时语音不被衰减(%.1f dB)', gSp));

%% 3) AGC
audio_proc_tx('reset', Pb);
quietIn = 200*sin(2*pi*300*(0:N*(nWarm+220)-1).'/P.audioFs);     % 约 -44 dBFS, 给 AGC 足够时间(rel 1.2s)收敛
y = run_tx(quietIn, Pb, N);
outDb = 20*log10(rms16(y(end-10*N:end))/32768);
check(abs(outDb - Pb.procAgcTargetDb) < 4, ...
    sprintf('轻语音被提到目标电平(%.1f dBFS, 目标 %d)', outDb, Pb.procAgcTargetDb));

audio_proc_tx('reset', Pb);
loudIn = 12000*sin(2*pi*300*(0:N*(nWarm+120)-1).'/P.audioFs);    % 约 -8.7 dBFS
y = run_tx(loudIn, Pb, N);
outDb = 20*log10(rms16(y(end-10*N:end))/32768);
check(abs(outDb - Pb.procAgcTargetDb) < 4, ...
    sprintf('响语音被压到目标电平(%.1f dBFS)', outDb));

%% 4) 预热期一直在讲话: 门限不能抬到语音电平
audio_proc_tx('reset', P);
talk = 3000*sin(2*pi*300*(0:N*nF-1).'/P.audioFs);                % 约 -23 dBFS, 全程讲话
y    = run_tx(talk, P, N);
gTk  = 20*log10(rms16(y(end-10*N:end)) / rms16(round(talk(end-10*N:end))));
check(gTk > -6, sprintf('预热期在讲话也不会把语音切掉(%.1f dB)', gTk));

%% 5) 静音段不被 AGC 提起
audio_proc_tx('reset', P);
y = run_tx([60*randn(N*nWarm,1); 60*randn(N*60,1)], P, N);
tailRms = rms16(y(end-10*N:end));
check(tailRms < 30, sprintf('长时间静音仍保持门关闭(尾段 RMS %.1f LSB)', tailRms));

%% 6) 帧边界连续性
audio_proc_tx('reset', Pb);
sig = 6000*sin(2*pi*300*(0:N*50-1).'/P.audioFs);
y   = run_tx(sig, Pb, N);
maxSlope = 6000*2*pi*300/P.audioFs;
check(max(abs(diff(double(y)))) < 2.0*maxSlope, ...
    sprintf('帧边界无跳变(最大相邻差 %.0f, 理论上限 %.0f)', max(abs(diff(double(y)))), maxSlope));

%% 7) 接收端高通
audio_proc_rx('reset', P);
yr = audio_proc_rx(5000*ones(N*20,1), P);
check(abs(mean(yr(end-3*N:end))) < 200, '接收端高通去掉直流');
audio_proc_rx('reset', P);
sr = 8000*sin(2*pi*300*(0:N*20-1).'/P.audioFs);
yr = audio_proc_rx(sr, P);
check(rms16(yr(end-5*N:end)) > 0.95*rms16(round(sr(end-5*N:end))), ...
    '接收端高通不削 300Hz');

audio_proc_tx('reset', P);
audio_proc_rx('reset', P);
fprintf('=== 全部通过 ===\n');
end

%% ---------- 局部函数 ----------
function r = rms16(x)
% 先转 double 再求 RMS; 直接对 int16 求平方会饱和到 32767
r = sqrt(mean(double(x(:)).^2));
end

function y = run_tx(x, P, N)
nF = numel(x) / N;
y  = zeros(N*nF, 1, 'int16');
for k = 1:nF
    y((k-1)*N+1 : k*N) = audio_proc_tx(int16(round(x((k-1)*N+1 : k*N))), P);
end
end

function check(cond, msg)
if cond
    fprintf('  通过  %s\n', msg);
else
    error('test_audio_proc: 失败 -> %s', msg);
end
end
