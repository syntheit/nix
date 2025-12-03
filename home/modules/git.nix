{ ... }:

{
  programs.git = {
    enable = true;
    # Configure Git to use SSH for GitHub URLs
    settings = {
      user.name = "Daniel Miller";
      user.email = "daniel@matv.io";
      url."git@github.com:".insteadOf = "https://github.com/";
    };
  };
}
