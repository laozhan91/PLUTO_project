function n = audio_player(varargin)
% audio_player.m  A-law 字节 / PCM → 抖动缓冲 → 声卡(墙钟驱动)
%
% 用法:
%   audio_player('init', P)              创建/复位播放器与缓冲
%   audio_player('prime', P)             init + 预热声卡(实时循环前调用, 吃掉启动开销)
%   audio_player(payloadBytes, P, seq)   推入一帧 A-law 字节; seq(uint8) 可省略
%   n = audio_player('tick', P)          按流逝时间向声卡写入样本, 返回写入点数
%   s = audio_player('stats')            返回统计 struct(good/dup/gap/under/queued)
%   y = audio_player('pull', P, m)       从缓冲取出 m 点返回(不写声卡, 供离线自检)
%   audio_player('release')              释放声卡设备
%
% 为什么墙钟驱动:
%   RX 每轮抓 8192 点(32.8ms)才有新数据, 而声卡需要 8kHz 连续供给。
%   若"每轮写 160 点", 每轮只补 20ms 音频 → 必然断音/整体变慢。
%   这里按 toc 计算"到现在为止应该播了多少样本", 只补差额, 与抓包节奏解耦。
%
% 丢帧处理:
%   - 重复帧(发射端 repmat 造成同 seq 重复出现)直接丢弃, 不再二次播放
%   - seq 跳变 d-1 帧 → 用"保持上一好帧 + 逐帧淡出"补齐, 消除空洞与爆音
%   - 缓冲下溢(帧还没到)同样用隐藏帧填, 长时间无好帧则静音
%
% 退出清缓存: clear audio_player

persistent adw adwFs buf cap rd cnt lastPcm lastSeq t0 written
persistent nGood nDup nGap nUnder

n = 0;
if nargin < 1
    error('audio_player: 至少需要 1 个输入');
end
if ischar(varargin{1})
    mode = lower(varargin{1});
else
    mode = 'push';
end

switch mode
    case 'init'
        doInit(varargin{2});

    case 'prime'
        % 供实时循环调用: init + 预热设备, 把启动开销挪到循环之前
        %   audioDeviceWriter 有三笔一次性开销: 建设备 ~1s、首块写入 ~0.3s、
        %   首次改变块长度 ~1.3s。这里一次性全部付掉, 循环里就不会突然卡住。
        P = varargin{2};
        doInit(P);
        if ~isempty(adw)
            try
                n0 = round(P.audioFs * 0.1);
                adw(zeros(n0, 1));
                adw(zeros(n0 + 37, 1));      % 触发一次尺寸切换
                pause(0.3);
            catch
                adw = [];
            end
        end
        t0 = tic;
        written = 0;

    case 'push'
        P = varargin{2};
        if isempty(buf)
            doInit(P);
        end
        seq = [];
        if numel(varargin) >= 3 && ~isempty(varargin{3})
            seq = uint8(varargin{3});
        end

        pcm = double(alaw_to_pcm16(uint8(varargin{1}(:))));

        if ~isempty(seq)
            if ~isempty(lastSeq)
                d = mod(double(seq) - double(lastSeq), 256);
                if d == 0
                    nDup = nDup + 1;                 % 重复帧
                    return;
                elseif d < 128
                    if d > 1
                        nGap = nGap + (d - 1);
                        pushSamples(concealSamples(d - 1, P, []));
                    end
                else
                    nDup = nDup + 1;                 % 迟到的旧帧
                    return;
                end
            end
            lastSeq = seq;
        end

        lastPcm = pcm;
        pushSamples(applyGain(pcm, P));
        nGood = nGood + 1;

    case 'tick'
        P = varargin{2};
        if isempty(t0)
            t0 = tic;  written = 0;
        end
        target = round(toc(t0) * P.audioFs);
        lag    = target - written;
        if lag > round(P.audioFs * 1.0)     % 落后超过 1s(设备曾长时间欠载): 重新对齐, 不追赶
            written = target;
            lag     = 0;
        end
        need = min(lag, round(P.audioFs * 0.1));    % 单次最多写 100ms
        if need <= 0
            return;
        end
        out = popSamples(need);
        if numel(out) < need
            nUnder = nUnder + 1;
            out = [out; concealSamples(0, P, need - numel(out))];
        end
        ensureDevice(P);
        adw(out);
        written = written + need;
        n = need;

    case 'pull'
        % 仅供离线自检: 从缓冲取出 m 点直接返回, 不写声卡
        P = varargin{2};
        m = varargin{3};
        out = popSamples(m);
        if numel(out) < m
            out = [out; concealSamples(0, P, m - numel(out))];
        end
        n = out;

    case 'stats'
        if isempty(nGood)
            doInit(struct('audioFs', 8000, 'audioFrameSec', 0.02));
        end
        n = struct('good', nGood, 'dup', nDup, 'gap', nGap, ...
                   'under', nUnder, 'queued', cnt);

    case 'release'
        if ~isempty(adw)
            try
                release(adw);
            catch
            end
            adw = [];
        end
        buf = [];  rd = 1;  cnt = 0;
        lastPcm = [];  lastSeq = [];
        t0 = [];  written = 0;

    otherwise
        error('audio_player: 未知命令 %s', mode);
end

%% ================= 嵌套函数(共享 persistent 状态) =================

function doInit(P)
    if ~isempty(adw) && adwFs ~= P.audioFs
        try
            release(adw);
        catch
        end
        adw = [];
    end
    frameN = round(P.audioFs * P.audioFrameSec);
    cap    = max(round(P.audioFs * pv(P, 'playBufSec', 0.5)), ...
                 pv(P, 'playTargetFrames', 2) * frameN);
    buf     = zeros(cap, 1);
    rd      = 1;
    cnt     = 0;
    lastPcm = [];
    lastSeq = [];
    nGood = 0;  nDup = 0;  nGap = 0;  nUnder = 0;

    % 提前创建设备: 首次打开约需 1s, 放在 init 里付掉, 不要落在实时循环中。
    % 打不开(无声卡环境)就退回懒创建, 不影响 push/stats 逻辑。
    try
        ensureDevice(P);
    catch
        adw = [];
    end
    t0 = tic;
    written = 0;
end

function v = pv(P, name, dflt)
    if isfield(P, name) && ~isempty(P.(name))
        v = P.(name);
    else
        v = dflt;
    end
end

function y = applyGain(x, P)
% x 为 A-law 解码后的 PCM, 量纲 ±32768; 声卡输入要求 ±1
    y = x / 32768 * pv(P, 'audioVolumeGain', 4);
    y = max(min(y, 1), -1);
end

function y = concealSamples(nFrames, P, nSamples)
% 保持上一好帧 + 逐帧淡出; nSamples 省略时取 nFrames 帧
    frameN = round(P.audioFs * P.audioFrameSec);
    if nargin < 3 || isempty(nSamples)
        nSamples = nFrames * frameN;
    end
    if nSamples <= 0
        y = zeros(0, 1);
        return;
    end
    fade    = pv(P, 'playFadePerMiss', 0.7);
    maxHold = pv(P, 'playMaxHoldFrames', 8);
    gain    = pv(P, 'audioVolumeGain', 4);

    y   = zeros(nSamples, 1);
    pos = 1;
    k   = 1;
    while pos <= nSamples
        if isempty(lastPcm) || k > maxHold
            seg = zeros(frameN, 1);             % 无好帧可保持 / 隐藏过久 → 静音
        else
            seg = lastPcm / 32768 * (gain * fade^k);    % lastPcm 为 ±32768 量纲
            seg = max(min(seg, 1), -1);
        end
        m = min(frameN, nSamples - pos + 1);
        y(pos : pos+m-1) = seg(1:m);
        pos = pos + m;
        k   = k + 1;
    end
end

function pushSamples(x)
    x = x(:);
    m = numel(x);
    if m == 0 || isempty(buf)
        return;
    end
    if m > cap
        x   = x(end-cap+1 : end);
        m   = cap;
        rd  = 1;
        cnt = 0;
    end
    if cnt + m > cap                        % 溢出: 丢最旧, 保低延迟
        drop = cnt + m - cap;
        rd   = mod(rd - 1 + drop, cap) + 1;
        cnt  = cnt - drop;
    end
    wr  = mod(rd - 1 + cnt, cap) + 1;
    idx = mod(wr - 1 + (0:m-1), cap) + 1;
    buf(idx) = x;
    cnt = cnt + m;
end

function y = popSamples(m)
    y = zeros(0, 1);
    m = min(m, cnt);
    if m <= 0 || isempty(buf)
        return;
    end
    idx = mod(rd - 1 + (0:m-1), cap) + 1;
    y   = buf(idx);
    rd  = mod(rd - 1 + m, cap) + 1;
    cnt = cnt - m;
end

function ensureDevice(P)
    if isempty(adw) || adwFs ~= P.audioFs
        if ~isempty(adw)
            try
                release(adw);
            catch
            end
        end
        adw   = audioDeviceWriter('SampleRate', P.audioFs);
        adw.SupportVariableSizeInput = true;    % 每次按墙钟写入的点数是变化的
        adwFs = P.audioFs;
    end
end

end
