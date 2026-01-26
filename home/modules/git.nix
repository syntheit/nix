{ ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user.name = "Daniel Miller";
      user.email = "daniel@matv.io";
    };
  };
}
