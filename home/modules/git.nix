{ vars, ... }:

{
  programs.git = {
    enable = true;
    signing.format = null;
    settings = {
      user.name = vars.user.fullname;
      user.email = vars.user.email;
    };
  };
}
