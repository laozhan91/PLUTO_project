function y = audio_proc_tx(x, P)
% audio_proc_tx.m  发射端音频前处理: 高通 → 自动噪声门 → 慢速 AGC → 峰值限幅
%
% 用法:
%   audio_proc_tx('reset', P)   复位内部状态(每次开始发射前调用)
%   y = audio_proc_tx(x, P)     处理一帧 int16 PCM, 返回 int16 PCM
%
% 为什么按这个顺序:
%   - 高通先做: 去掉 DC 与电源嗡声, 否则它们会被后面的 AGC 当成"信号"去归一化
%   - 噪声门在 AGC 之前: AGC 只负责把语音拉到目标电平, 不会顺手把底噪一起提上来
%   - AGC 在门之后、且门关闭时冻结增益: 静音段增益原地不动, 否则底噪会被慢慢放大
%     (这正是"底噪越听越大"的经典成因)
%
% 门限与判决必须用同一种"电平":
%   底噪估计与门限都基于帧/块 RMS, 所以判决也必须用块 RMS。
%   若用 abs()+慢释放的峰值包络去比 RMS 门限, 高斯噪声的峰值比 RMS 高约 10dB,
%   噪声会一直"看起来"贴在门限上, 门不关、AGC 又把底噪当轻语音猛提。
%
% 底噪估计:
%   - 预热 P.procNoiseWarmFrames 帧(默认 25 帧 = 0.5s), 取各帧 RMS 的 20% 分位数
%     → 比中位数更抗"预热期正好在说话"
%   - 初值上限 P.procNoiseInitMaxDb(默认 -35dBFS), 防止把语音误当底噪
%   - 之后相对初值最多再升 P.procNoiseRiseDb(默认 6dB), 长时间讲话也不会把门限"喂"上去
% 因此每次开始发射后请保持安静约 0.5s(这段时间为直通)。
%
% 退出清缓存: clear audio_proc_tx

persistent b1 a1 b2 a2 fs zi1 zi2 gateDb
persistent noiseDb noiseDb0 warmVals warm agcDb prevAgcDb

y = int16([]);

if ischar(x)
    if strcmpi(x, 'reset')
        b1 = []; a1 = []; b2 = []; a2 = []; fs = [];
        zi1 = []; zi2 = []; gateDb = [];
        noiseDb = []; noiseDb0 = []; warmVals = []; warm = [];
        agcDb = []; prevAgcDb = [];
        return;
    end
    error('audio_proc_tx: 未知命令 %s', x);
end

x = double(x(:));
N = numel(x);
if N == 0
    return;
end

%% ---- 初始化(按采样率) ----
if isempty(fs) || fs ~= P.audioFs
    fs = P.audioFs;
    fc = pv(P, 'procHpHz', 90);
    [b1, a1] = hp_biquad(fc, fs, 0.5412);
    [b2, a2] = hp_biquad(fc, fs, 1.3066);
    zi1 = zeros(2,1);  zi2 = zeros(2,1);
    gateDb = 0;
    noiseDb = [];      noiseDb0 = []; warmVals = zeros(1,0);  warm = 0;
    agcDb = 0;         prevAgcDb = 0;
end

%% ---- 1) 高通(4 阶 Butterworth = 两级 biquad) ----
[hp, zi1] = filter(b1, a1, x, zi1);
[hp, zi2] = filter(b2, a2, hp, zi2);

%% ---- 2) 底噪估计 ----
frameDb = db_rms(hp);
nWarm   = pv(P, 'procNoiseWarmFrames', 25);

if warm < nWarm
    warmVals(warm+1) = frameDb;
    warm = warm + 1;
    noiseDb = noise_init(warmVals(1:warm), pv(P, 'procNoiseInitMaxDb', -35));
    noiseDb0 = noiseDb;
    y = int16(clip16(hp));
    return;                       % 预热期直通(已做高通)
end

if frameDb < noiseDb
    noiseDb = 0.7*noiseDb + 0.3*frameDb;                       % 快速跟随更安静的帧
else
    noiseDb = 0.9995*noiseDb + 0.0005*frameDb;                 % 极慢上升
end
noiseDb = min(noiseDb, noiseDb0 + pv(P, 'procNoiseRiseDb', 6));

%% ---- 3) 噪声门(短块 RMS 判决 + 平滑增益) ----
openDb  = noiseDb + pv(P, 'procGateOpenDb', 9);
closeDb = noiseDb + pv(P, 'procGateCloseDb', 4);
floorDb = pv(P, 'procGateFloorDb', -26);

aOpen  = exp(-1 / (pv(P, 'procGateAttMs', 5)/1000   * fs));   % 开门: 快
aClose = exp(-1 / (pv(P, 'procGateRelMs', 120)/1000 * fs));   % 关门: 慢

blk    = max(1, round(pv(P, 'procGateBlkMs', 5)/1000 * fs));
nBlk   = ceil(N / blk);
gTarget = zeros(N,1);
blkDb  = zeros(nBlk,1);
for b = 1:nBlk
    i1 = (b-1)*blk + 1;
    i2 = min(b*blk, N);
    blkDb(b) = db_rms(hp(i1:i2));
    if blkDb(b) <= closeDb
        gTarget(i1:i2) = floorDb;
    elseif blkDb(b) >= openDb
        gTarget(i1:i2) = 0;
    else
        gTarget(i1:i2) = floorDb * (openDb - blkDb(b)) / (openDb - closeDb);
    end
end

gSm = zeros(N,1);
for n = 1:N
    if gTarget(n) > gateDb
        gateDb = aOpen*gateDb  + (1-aOpen)*gTarget(n);
    else
        gateDb = aClose*gateDb + (1-aClose)*gTarget(n);
    end
    gSm(n) = gateDb;
end
yg = hp .* (10.^(gSm/20));

%% ---- 4) 慢速 AGC(门关闭时冻结) ----
dt        = N / fs;
openRatio = mean(gSm > -6);
outDb     = db_rms(yg);
prevAgcDb = agcDb;

if openRatio > 0.3                    % 该帧大部分是语音才调整增益
    % 误差必须用"当前增益下"的实际输出电平, 否则增益会朝同一方向一直积分下去
    err = pv(P, 'procAgcTargetDb', -18) - (outDb + agcDb);
    if err < 0
        k = 1 - exp(-dt / (pv(P, 'procAgcAtkMs', 150)/1000));    % 过响: 压得快
    else
        k = 1 - exp(-dt / (pv(P, 'procAgcRelMs', 1200)/1000));   % 过轻: 提得慢
    end
    agcDb = agcDb + err*k;
    agcDb = min(max(agcDb, pv(P, 'procAgcMinDb', -20)), pv(P, 'procAgcMaxDb', 26));
end

% 峰值天花板: AGC 只按 RMS 归一, 而滤波会改变相位、把峰值因数抬高
% (实测 12 次谐波信号过一级高通后峰值 +4.1dB, RMS 几乎不变)。
% 这里按本帧峰值算出允许的最大增益, 并对增益斜坡的两个端点都做夹取,
% 保证整帧输出峰值不超过 procAgcPeakCeilDb;
% 否则收端回放时峰值会被推出 ±1 → 硬削顶, 听感像加了失真效果器。
ceilDb = pv(P, 'procAgcPeakCeilDb', -3);
peakDb = 20*log10(max(abs(yg)) / 32768 + 1e-12);
gHi    = ceilDb - peakDb;                 % 本帧允许的最大增益
agcDb  = min(agcDb, gHi);

g0    = min(prevAgcDb, gHi);              % 斜坡起点也要受限, 否则帧首会超
gRamp = linspace(g0, agcDb, N).';
ya    = yg .* (10.^(gRamp/20));

%% ---- 5) 峰值限幅(安全网) ----
y = int16(round(clip16(ya)));
end

%% ================= 局部函数 =================
function v = db_rms(seg)
v = 20*log10(sqrt(mean(seg.^2)) / 32768 + 1e-12);
end

function v = noise_init(vals, maxDb)
% 预热期帧 RMS 的 20% 分位数, 并夹在 -35dBFS 以下(防止把语音当底噪)
v = sort(vals(:));
idx = max(1, round(0.2*numel(v)));
v = min(v(idx), maxDb);
end

function v = clip16(x)
v = max(min(x, 0.99*32768), -0.99*32768);
end

function v = pv(P, name, dflt)
if isfield(P, name) && ~isempty(P.(name))
    v = P.(name);
else
    v = dflt;
end
end
