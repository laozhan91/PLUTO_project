function n = audio_player(varargin)
% audio_player.m  A-law 字节 / PCM → 抖动缓冲 → 声卡(墙钟驱动)
%
% 用法:
%   audio_player('init', P)              创建/复位播放器与缓冲
%   audio_player('prime', P)             init + 预热声卡(实时循环前调用, 吃掉启动开销)
%   audio_player(payloadBytes, P, seq)   推入一帧 A-law 字节; seq(uint8) 可省略
%   n = audio_player('tick', P)          按流逝时间向声卡写入样本, 返回写入点数
%   s = audio_player('stats')            返回统计 struct(good/dup/gap/under/queued/clip)
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
persistent nGood nDup nGap nUnder nClip

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
        if rx_hpf_on(P)
            pcm = audio_proc_rx(pcm, P);    % 去直流 / 低频嗡声(状态跨帧保留)
        end

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
        raw  = pcm / 32768 * pv(P, 'audioVolumeGain', 4);
        nClip = nClip + sum(abs(raw) >= 1);      % 削顶计数: 有此计数说明回放增益过大
        pushSamples(max(min(raw, 1), -1));
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
                   'under', nUnder, 'queued', cnt, 'clip', nClip);

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
    if rx_hpf_on(P)
        audio_proc_rx('reset', P);      % 高通状态清零, 避免上一轮遗留
    end
    frameN = round(P.audioFs * P.audioFrameSec);
    cap    = max(round(P.audioFs * pv(P, 'playBufSec', 0.5)), ...
                 pv(P, 'playTargetFrames', 2) * frameN);
    buf     = zeros(cap, 1);
    rd      = 1;
    cnt     = 0;
    lastPcm = [];
    lastSeq = [];
    nGood = 0;  nDup = 0;  nGap = 0;  nUnder = 0;  nClip = 0;

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

function tf = rx_hpf_on(P)
    tf = isfield(P, 'enableRxHPF') && ~isempty(P.enableRxHPF) && logical(P.enableRxHPF);
end

function y = concealSamples(nFrames, P, nSamples)
% 丢帧隐藏: 基音周期波形延拓 + 逐帧淡出
%   旧实现"整帧重复上一帧 20ms"会产生 50Hz 的幅度调制 → 机器人声/电音。
%   这里取上一好帧末尾的一个基音周期做循环延拓, 波形连续且基音对齐,
%   听感接近自然延音, 不再有整帧边界造成的颤音。
    frameN = round(P.audioFs * P.audioFrameSec);
    if nargin < 3 || isempty(nSamples)
        nSamples = nFrames * frameN;
    end
    y = zeros(nSamples, 1);
    if nSamples <= 0
        return;
    end
    if isempty(lastPcm)
        return;                              % 无参考: 全静音
    end
    fade    = pv(P, 'playFadePerMiss', 0.7);
    maxHold = pv(P, 'playMaxHoldFrames', 8);
    gain    = pv(P, 'audioVolumeGain', 4);

    T    = pitch_period(lastPcm, P.audioFs);        % 基音周期(样本)
    idx  = mod((0:nSamples-1).', T) + 1;            % 循环延拓索引
    tmpl = double(lastPcm(end-T+1:end));            % ±32768 量纲
    seg  = tmpl(idx);                               % 连续波形(无帧边界跳变)

    % 逐样本连续淡出: 避免逐帧台阶(每 20ms 跳 -3dB)造成的"呼吸"调制
    env = fade .^ ((0:nSamples-1).' / frameN);
    if ceil(nSamples / frameN) > maxHold
        env(maxHold*frameN + 1 : end) = 0;          % 隐藏过久 → 静音
    end

    y = seg .* env / 32768 * gain;
    y = max(min(y, 1), -1);
end

function T = pitch_period(x, fs)
% 自相关估计基音周期(约 100~350Hz @8kHz); 清音/噪声相关性弱则退回固定周期
    x = double(x(:));
    x = x - mean(x);
    n = numel(x);
    minLag = round(fs/350);                          % 350Hz 上限
    maxLag = min(round(fs/100), floor(n/2));         % 100Hz 下限(受帧长限制)
    if maxLag <= minLag || n < 2*minLag
        T = round(fs/100);
        return;
    end
    c = conv(x, x(end:-1:1));                        % c(n+lag) = sum x(m)*x(m+lag)
    r = c(n : n+maxLag).';
    r = r / max(r(1), 1e-12);
    seg = r(minLag+1 : maxLag+1);
    [pk, im] = max(seg);
    if pk < 0.35                                    % 清音/噪声: 相关性弱
        T = round(fs/100);
    else
        T = minLag + im - 1;
    end
    T = max(T, minLag);
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
