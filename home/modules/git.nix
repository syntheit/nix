{ vars, pkgs, ... }:

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
      merge.conflictstyle = "diff3"; # show base in merge conflicts (works with delta)
    };
  };

  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate = true;
      side-by-side = true;
      line-numbers = true;
    };
  };

  programs.lazygit = {
    enable = true;
    settings = {
      gui.showCommandLog = false;
      git.paging = {
        colorArg = "always";
        pager = "${pkgs.delta}/bin/delta --paging=never";
      };
    };
  };

  xdg.configFile."git/allowed_signers".text = ''
    ${vars.user.email} ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdRcH2UWe31VdU62j3Ksbb6LDyS1APNW1BQMM8mvsej ${vars.user.email}
  '';
}
