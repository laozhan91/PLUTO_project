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
    % 🚨 修复 1：一帧总长(1328 bits) = 664 符号 = 2656 采样点 (sps=4)
    % 必须设置成 8192 才能保证一次抓取能完整覆盖至少 3 帧！
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

    %% ===================== app/ 层音频参数 =====================
    P.audioFs         = 8000;                           
    P.audioBits       = 16;                             
    P.audioFrameSec   = 0.02;                           
    P.audioVolumeGain   = 4;         
    P.audioBitsPerFrame = P.audioFs * P.audioBits * P.audioFrameSec;

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