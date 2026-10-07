{ vars, ... }:

# Root helper so Telmo can show and toggle Wi-Fi auto-join without prompts.
# It only answers this user, and only processes signed by this team.
{
  users.users.${vars.user.name}.uid = 501;
  services.telmo-helper = {
    enable = true;
    user = vars.user.name;
    teamId = "6NHZWHQX37";
  };
}
