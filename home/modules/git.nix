{ vars, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = vars.user.fullname;
      user.email = vars.user.email;
    };
  };
}
