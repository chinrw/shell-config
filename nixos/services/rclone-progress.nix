{ username, ... }:
let
  readerGroup = "hermes";
in
{
  users.groups.${readerGroup} = { };

  systemd.tmpfiles.rules = [
    "d /var/lib/rclone-progress 2750 ${username} ${readerGroup} - -"
    "d /var/lib/rclone-progress/view 2750 ${username} ${readerGroup} - -"
    "d /var/lib/rclone-progress/view/native 2750 ${username} ${readerGroup} m:7d -"
  ];
}
