{ ... }:

{
  # Set zen-browser as default browser for HTTP/HTTPS links
  xdg.mimeApps.defaultApplications = {
    "text/html" = "zen.desktop";
    "x-scheme-handler/http" = "zen.desktop";
    "x-scheme-handler/https" = "zen.desktop";
    "x-scheme-handler/about" = "zen.desktop";
    "x-scheme-handler/unknown" = "zen.desktop";
    # Set Thunderbird as default email client
    "x-scheme-handler/mailto" = "thunderbird.desktop";
    "message/rfc822" = "thunderbird.desktop";
    "application/x-extension-eml" = "thunderbird.desktop";
    # Set Thunderbird as default calendar client
    "text/calendar" = "thunderbird.desktop";
    "text/x-vcalendar" = "thunderbird.desktop";
    "application/ics" = "thunderbird.desktop";
  };
}
