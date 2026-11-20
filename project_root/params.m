function P = params(mode)
% params.m  全局参数控制台（唯一真相源）
% mode: 'sim' | 'loopback' | 'overair'

    P.mode = mode;

    %% ===================== 调制与码率 =====================
    P.modulation = 'QPSK';                              % 'BPSK' | 'QPSK'
    P.M          = 2^(strcmpi(P.modulation,'QPSK')+1);
    P.bps        = log2(P.M);

    %% ===================== 采样率与成型 =====================
    if strcmp(mode,'sim')
        P.sps  = 8;
        P.nBits = 1e5;
    else
        P.sps  = 4;                                     % 1MHz / 4 = 250 ksym/s
        P.nBits = 5e4;
    end
    P.rolloff = 0.35;
    P.span    = 6;

    %% ===================== 射频参数（硬件生效） =====================
    P.centerFreq   = 2.4e9;
    P.basebandRate = 250e3;
    P.txGain       = 0;                               % 发射衰减（先调大一点试试）
    P.rxGain       = 45;                                % 接收增益 (30~40 比较安全)
    P.radioID_tx   = 'usb:0';
    P.radioID_rx   = 'usb:0';                           % 单机环回 usb:0；双机改为 'usb:1'

    %% ===================== 接收缓冲管理 =====================
    % 一帧 1328 bit(无 FEC) / 2072 bit(RS 整帧) = 664 / 1036 符号
    %   = 2656 / 4144 采样点 (sps=4)，8192 点可完整覆盖 1.9~3 帧
    P.rxFrameLength   = 8192;                           
    P.maxBufferedBits = 2e6;                            
    P.minFrameBits    = 512;                            
    
    %% ===================== 同步开关 =====================
    P.enableTimingSync = true;
    P.enablePhaseTrack = true;

    %% ===================== app/ 层帧协议 =====================
    P.preambleHex  = 'AA55';                            % 帧头
    P.preambleBits = [1 0 1 0 1 0 1 0  ...               % 0xAA55 的比特展开
                      0 1 0 1 0 1 0 1];
    P.crcType      = 'CRC-8';                           % 看你原来是用 CRC8
    P.lengthFieldBits = 8;                              % 长度字段 8 bit
    P.crcFieldBits    = 8;                              % CRC 字段 8 bit

    %% ===================== app/ 层 FEC(RS 整帧协议) =====================
    % enableFEC = false : 旧格式 [AA55][len][payload][CRC-8][55AA]          1328 bit
    % enableFEC = true  : [同步字 AA55AA55][RS(255,223) 码字]               2072 bit
    %   逻辑帧 [AA55][len][seq][payload 160B][CRC-8][55AA] = 167B, 补零到 223B
    %   帧头/长度/序号/CRC/帧尾全在 RS 保护范围内, 残余错误由 CRC-8 兜底丢弃
    %   ⚠️ 发射端与接收端必须使用同一个 enableFEC 值
    P.enableFEC     = false;
    P.fecN          = 255;
    P.fecK          = 223;
    P.fecT          = (P.fecN - P.fecK) / 2;            % 可纠 16 个符号错
    P.fecSyncBytes  = uint8([0xAA; 0x55; 0xAA; 0x55]);
    P.fecSyncMaxErr = 2;                                % 同步字容 2 bit 错
    P.fecFrameBits  = numel(P.fecSyncBytes)*8 + P.fecN*8;   % 2072 bit

    %% ===================== app/ 层音频参数 =====================
    P.audioFs         = 8000;                           
    P.audioBits       = 16;                             
    P.audioFrameSec   = 0.02;                           
    P.audioVolumeGain   = 4;         
    P.audioBitsPerFrame = P.audioFs * P.audioBits * P.audioFrameSec;

    %% ===================== app/ 层播放缓冲 =====================
    % 墙钟驱动播放: 每轮按流逝时间写入 Fs*dt 个样本, 与抓包节奏解耦, 不会漂移
    P.playBufSec        = 0.5;   % 环形缓冲容量(秒)
    P.playTargetFrames  = 2;     % 抖动缓冲深度(帧), 决定缓冲容量下限
    P.playFadePerMiss   = 0.7;   % 丢帧隐藏: 每多丢一帧的衰减系数
    P.playMaxHoldFrames = 8;     % 连续隐藏超过该帧数则静音, 防止嗡嗡声

    %% ===================== 量化验收门限 =====================
    P.thresholds.isi_dB          = -25;
    P.thresholds.evm_pct         = 15;
    P.thresholds.evm_corr        = 10;
    P.thresholds.timing_conv_sym = 200;
    P.thresholds.phase_rms_deg   = 5;
   
    %% ===================== 追加参数 ========================
    P.maxBerLag   = 2000;
    P.berSkipBits = 0;

    %% ===================== 硬件频偏校准 =====================
    % 尝试加载校准文件，如果不存在则使用默认值 0
    if exist('pluto_cal.mat', 'file')
        calData = load('pluto_cal.mat');
        P.rxPPMCorrection = calData.ppmToAdd;
    else
        P.rxPPMCorrection = 0; % 默认不校正
    end
end