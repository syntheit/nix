{ vars, ... }:

{
  programs.git = {
    enable = true;
    signing = {
      format = "ssh";
      key = "~/.ssh/mainkey.pub";
      signByDefault = true;
    };
    settings = {
      user.name = vars.user.fullname;
      user.email = vars.user.email;
      gpg.ssh.allowedSignersFile = "~/.config/git/allowed_signers";
    };
  };

  xdg.configFile."git/allowed_signers".text = ''
    ${vars.user.email} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej ${vars.user.email}
  '';
}
