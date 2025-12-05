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
    # Set Loupe as default image viewer
    "image/png" = "loupe.desktop";
    "image/jpeg" = "loupe.desktop";
    "image/jpg" = "loupe.desktop";
    "image/gif" = "loupe.desktop";
    "image/bmp" = "loupe.desktop";
    "image/webp" = "loupe.desktop";
    "image/svg+xml" = "loupe.desktop";
    "image/tiff" = "loupe.desktop";
    "image/x-icon" = "loupe.desktop";
    "image/vnd.microsoft.icon" = "loupe.desktop";
    "image/x-ico" = "loupe.desktop";
    "image/ico" = "loupe.desktop";
    "image/heic" = "loupe.desktop";
    "image/heif" = "loupe.desktop";
    # Set Papers as default PDF viewer
    "application/pdf" = "papers.desktop";
  };
}
