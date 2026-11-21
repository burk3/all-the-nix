{pkgs, config, lib, ...}:
let cfg = config.t11s.personal.kernel-mail; in
{
  options.t11s.personal.kernel-mail.enable = lib.mkEnableOption "configure git for sending kernel mail";
  config = lib.mkIf cfg.enable {
    programs.git.package = pkgs.git.override { sendEmailSupport = true; };
    programs.git.settings = {
      user.name = "Burke Cates";
      user.email = "burke.cates@gmail.com";
      sendemail = {
        from = "Burke Cates <burke.cates@gmail.com>";
        smtpServer = "smtp.gmail.com";
        smtpServerPort = 587;
        smtpEncryption = "tls";
        smtpUser = "burke.cates@gmail.com";
        smtpAuth = "OAUTHBEARER";
        suppresscc = "self";
        confirm = "always";
      };
      # "" clears any global helper for this host, then the Gmail OAuth one
      credential."smtp://smtp.gmail.com:587".helper = [
        ""
        "${pkgs.git-credential-email}/bin/git-credential-gmail"
      ];
    };

    home.packages = with pkgs; [
      # ...existing...
      git-credential-email
    ];
  };
}
