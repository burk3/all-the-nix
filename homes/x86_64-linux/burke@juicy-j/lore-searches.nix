# Burke's public lore-watch searches (t11s.loreWatch.searches,
# modules/home/lore-watch): the ASUS Zenbook A16 / Glymur subsystems and
# topics. Searches about his own threads and planned replies are not in this
# (public) repo: they live in ~/.config/lore-watch/searches.json
# (t11s.loreWatch.searchFiles), merged at run time. Drop one with
# t11s.loreWatch.searches.<name>.enable = false.
#
# Each entry is a Maildir folder <dir>/<name> fed by one saved lei search
# against https://lore.kernel.org/all/:
#   query    public-inbox search syntax: dfn: (file in a diff), s: (subject),
#            f: (from), m: (Message-ID), d:FROM.. (date), bare words (body).
#            dfn:a/b/c matches any path that starts with a/b/c.
#   threads  also fetch every message in each matching thread (replies,
#            reviews). Replies keep the subject, so s: searches don't need it;
#            dfn: searches do (replies quote the diff, they don't carry one).
#   ours     a thread Burke is in: `lore-new replies` lists messages here that
#            are not from him.
#   lookback how far back `lei up` asks lore again every lookbackEvery (6 h;
#            other runs use quickLookback, 1 day). lei's --remote-fudge-time:
#            lei up only sees matches newer than its last run minus this, and
#            --threads only expands those, so a reply to an older match is
#            missed unless the reply matches by itself. Thread searches use
#            "7.days" (reviews of patches up to a week old).
#
# Every open-ended search is bounded by date (d:2026-10-01..) so the first
# sync stays small. Volumes are lore
# matches for 2026-10-01..10-28 (28 days), measured 2026-10-28.
#
# A changed query re-creates that search's Maildir on the next run.
let
  since = "d:2026-10-01..";
  # `dfn:` terms OR'ed together.
  files = paths: "(" + builtins.concatStringsSep " OR " (map (p: "dfn:${p}") paths) + ")";
in
{
  # --- files the A16 kernel queue (glymur-flake) patches -------------------

  files-usb-phy = {
    description = "QMP combo PHY, eUSB2 repeaters (SMB2370), M31/SNPS eUSB2";
    query =
      files [
        "drivers/phy/qualcomm/phy-qcom-qmp-combo.c"
        "drivers/phy/qualcomm/phy-qcom-eusb2-repeater.c"
        "drivers/phy/qualcomm/phy-qcom-m31-eusb2.c"
        "drivers/phy/phy-snps-eusb2.c"
      ]
      + " AND ${since}";
    lookback = "7.days";
    threads = true; # 98
  };

  files-audio = {
    description = "qcom SoundWire, WSA884x, WCD9378, AudioReach/q6apm, X1E machine driver, LPASS LPI";
    query =
      files [
        "drivers/soundwire/qcom.c"
        "sound/soc/codecs/wsa884x.c"
        "sound/soc/codecs/wcd9378"
        "sound/soc/qcom/qdsp6/audioreach"
        "sound/soc/qcom/qdsp6/q6apm"
        "sound/soc/qcom/x1e80100.c"
        "drivers/pinctrl/qcom/pinctrl-sm8650-lpass-lpi.c"
      ]
      + " AND ${since}";
    lookback = "7.days";
    threads = true; # 135
  };

  files-sdca = {
    description = "SDCA core (WCD9378 builds on it); busy with Intel/Cirrus work, so no threads";
    query = "dfn:sound/soc/sdca AND ${since}";
    threads = false; # 12 (610 with threads, together with files-audio)
  };

  files-ath12k = {
    description = "ath12k patches about QCC2072, MHI, suspend/resume or MLO";
    query = "dfn:drivers/net/wireless/ath/ath12k AND (QCC2072 OR s:mhi OR s:resume OR s:suspend OR s:MLO) AND ${since}";
    threads = false; # 12 (ath12k threads pull in thousands)
  };

  files-ec-rtc = {
    description = "ASUS Glymur EC driver and binding, rtc-qcom-glink";
    query =
      files [
        "drivers/platform/arm64/asus-glymur-ec.c"
        "asus,zenbook-a16-ux3607oa-ec.yaml"
        "drivers/rtc/rtc-qcom-glink.c"
      ]
      + " AND ${since}";
    lookback = "7.days";
    threads = true; # 17
  };

  files-fastrpc-glink = {
    description = "fastrpc (remote heap) and pmic_glink";
    query =
      files [
        "drivers/misc/fastrpc.c"
        "drivers/soc/qcom/pmic_glink"
      ]
      + " AND ${since}";
    threads = false; # ~30
  };

  files-clk-glymur = {
    description = "Glymur clock controllers (gcc, dispcc, videocc, gpucc, ...)";
    query = "dfn:drivers/clk/qcom AND dfn:glymur AND ${since}";
    threads = false; # 9
  };

  files-msm-dp = {
    description = "msm DP/eDP controller (eDP link training, USB-C DP)";
    query = "dfn:drivers/gpu/drm/msm/dp AND ${since}";
    threads = false; # 40
  };

  files-dts-glymur = {
    description = "Glymur DTs, including glymur-asus-zenbook-a16-ux3607oa.dts";
    query = "dfn:arch/arm64/boot/dts/qcom/glymur AND ${since}";
    threads = false; # 37
  };

  files-gpu-camera = {
    description = "Adreno X2 (a8xx) and the A16 cameras (HM1092, OV02C10, Glymur CAMSS)";
    query = "(dfn:drivers/media/i2c/hm1092.c OR dfn:drivers/media/i2c/ov02c10.c OR (dfn:drivers/media/platform/qcom/camss AND glymur) OR (dfn:drivers/gpu/drm/msm/adreno AND (glymur OR X2-85 OR X2-90 OR a8xx))) AND ${since}";
    threads = false; # 39
  };

  # --- topics ----------------------------------------------------------------

  topic-glymur = {
    description = "any subject that names Glymur (replies included: they keep the subject)";
    query = "s:glymur AND ${since}";
    threads = false; # 227
  };

  topic-zenbook-a16 = {
    description = "the A16 by name anywhere in a message";
    query = ''(UX3607 OR "zenbook a16" OR zenbook-a16) AND ${since}'';
    lookback = "7.days";
    threads = true; # 173
  };

  topic-x1e-dts = {
    description = "X1E80100/Hamoa DT work (the A16's DT follows its patterns)";
    query = "(s:x1e80100 OR s:hamoa) AND (dfn:arch/arm64/boot/dts/qcom OR s:dts) AND ${since}";
    threads = false; # 50
  };

  # --- people, on these subjects only ---------------------------------------

  people-qcom = {
    description = "Qualcomm/Linaro maintainers and authors we track, on Glymur/X1E, audio, PHY or Glymur DT";
    query =
      "(f:konrad.dybcio OR f:konradybcio OR f:srinivas.kandagatla OR f:srini@kernel.org"
      + " OR f:wesley.cheng OR f:abel.vesa OR f:abelvesa OR f:krishna.kurapati"
      + " OR f:nabige.aala OR f:taniya.das OR f:manivannan.sadhasivam"
      + " OR f:dmitry.baryshkov OR f:johan@kernel.org)"
      + " AND (glymur OR UX3607 OR x1e80100 OR hamoa OR dfn:sound/soc/qcom"
      + " OR dfn:drivers/soundwire OR dfn:drivers/phy/qualcomm"
      + " OR dfn:arch/arm64/boot/dts/qcom/glymur OR s:usb43dp OR s:eusb2)"
      + " AND ${since}";
    threads = false; # 243
  };
}
