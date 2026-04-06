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
    # Set File Roller as default archive handler
    "application/zip" = "org.gnome.FileRoller.desktop";
    "application/x-tar" = "org.gnome.FileRoller.desktop";
    "application/gzip" = "org.gnome.FileRoller.desktop";
    "application/x-gzip" = "org.gnome.FileRoller.desktop";
    "application/x-bzip2" = "org.gnome.FileRoller.desktop";
    "application/x-xz" = "org.gnome.FileRoller.desktop";
    "application/x-7z-compressed" = "org.gnome.FileRoller.desktop";
    "application/x-rar" = "org.gnome.FileRoller.desktop";
    "application/x-compressed-tar" = "org.gnome.FileRoller.desktop";
    # Set Papers as default document viewer
    "application/pdf" = "papers.desktop";
    "application/epub+zip" = "papers.desktop";
    "image/vnd.djvu" = "papers.desktop";
    "application/postscript" = "papers.desktop";
    "application/oxps" = "papers.desktop";
    "application/vnd.ms-xpsdocument" = "papers.desktop";
    "application/x-cbz" = "papers.desktop";
    "application/x-cbr" = "papers.desktop";
  };
}
