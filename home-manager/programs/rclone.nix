{ config, lib, pkgs, ... }:

let
  rcloneService =
    { name
    , REMOTE_NAME
    , REMOTE_PATH ? "/"
    , MOUNT_DIR ? "%h/mounts/${name}"
    , POST_MOUNT_SCRIPT ? ''""''
    , RCLONE_RC_ON ? "false"
    , RCLONE_TEMP_DIR ? "/tmp/rclone/%u/${name}"
    , RCLONE_TPSLIMIT ? "0"
    , RCLONE_BWLIMIT ? "0"
    , RCLONE_MOUNT_DAEMON_TIMEOUT ? "0"
    , RCLONE_MOUNT_MULTI_THREAD_STREAMS ? "4"
    , RCLONE_MOUNT_TIMEOUT ? "10m"
    , RCLONE_MOUNT_TRANSFER ? "4"
    , RCLONE_MOUNT_DIR_CACHE_TIME ? "5m"
    , RCLONE_MOUNT_MAX_READ_AHEAD ? "256k"
    , RCLONE_MOUNT_POLL_INTERVAL ? "1m0s"
    , RCLONE_MOUNT_UMASK ? "022"
    , RCLONE_MOUNT_VFS_CACHE_MAX_AGE ? "1h0m0s"
    , RCLONE_MOUNT_VFS_CACHE_MAX_SIZE ? "128G"
    , RCLONE_MOUNT_VFS_CACHE_MODE ? "writes"
    , RCLONE_MOUNT_VFS_CACHE_POLL_INTERVAL ? "1m0s"
    , RCLONE_MOUNT_VFS_READ_CHUNK_SIZE ? "128M"
    , RCLONE_MOUNT_VFS_READ_CHUNK_SIZE_LIMIT ? "off"
    }: {
      "rclone-${name}" = {
        Unit = {
          Description = "RClone mount of users remote %i using filesystem permissions";
          Documentation = "http://rclone.org/docs/";
          After = "network-online.target";
        };
        Install = {
          WantedBy = [ "default.target" ];
        };

        Service = {
          Type = "notify";
          TimeoutSec = "900";
          ExecStart = ''${pkgs.rclone}/bin/rclone mount \
            --config=${config.xdg.configHome}/rclone/rclone.conf \
            --allow-other \
            --default-permissions \
            --rc=${RCLONE_RC_ON} \
            --cache-tmp-upload-path=${RCLONE_TEMP_DIR}/upload \
            --cache-chunk-path=${RCLONE_TEMP_DIR}/chunks \
            --cache-workers=8 \
            --transfers=${RCLONE_MOUNT_TRANSFER} \
            --cache-writes \
            --cache-dir=${RCLONE_TEMP_DIR}/vfs \
            --cache-db-path=${RCLONE_TEMP_DIR}/db \
            --tpslimit=${RCLONE_TPSLIMIT} \
            --multi-thread-streams=${RCLONE_MOUNT_MULTI_THREAD_STREAMS} \
            --no-modtime \
            --drive-use-trash \
            --stats=0 \
            --checkers=16 \
            --bwlimit=${RCLONE_BWLIMIT} \
            --cache-info-age=60m \
            --attr-timeout=1s \
            --timeout=${RCLONE_MOUNT_TIMEOUT} \
            --daemon-timeout=${RCLONE_MOUNT_DAEMON_TIMEOUT} \
            --dir-cache-time=${RCLONE_MOUNT_DIR_CACHE_TIME} \
            --dir-perms=0777 \
            --file-perms=0666 \
            --uid=%U \
            --gid=%G \
            --max-read-ahead=${RCLONE_MOUNT_MAX_READ_AHEAD} \
            --poll-interval=${RCLONE_MOUNT_POLL_INTERVAL} \
            --umask=${RCLONE_MOUNT_UMASK} \
            --vfs-cache-max-age=${RCLONE_MOUNT_VFS_CACHE_MAX_AGE} \
            --vfs-cache-max-size=${RCLONE_MOUNT_VFS_CACHE_MAX_SIZE} \
            --vfs-cache-mode=${RCLONE_MOUNT_VFS_CACHE_MODE} \
            --vfs-cache-poll-interval=${RCLONE_MOUNT_VFS_CACHE_POLL_INTERVAL} \
            --vfs-read-chunk-size=${RCLONE_MOUNT_VFS_READ_CHUNK_SIZE} \
            --vfs-read-chunk-size-limit=${RCLONE_MOUNT_VFS_READ_CHUNK_SIZE_LIMIT} \
            ${REMOTE_NAME}:${REMOTE_PATH} ${MOUNT_DIR}
      '';
          ExecStartPost = "${pkgs.bash}/bin/bash -c ${POST_MOUNT_SCRIPT}";
          ExecStop = "${pkgs.fuse}/bin/fusermount -zu ${MOUNT_DIR}";
          Environment = [ "PATH=/run/wrappers/bin/:$PATH" ];
          Restart = "always";
          RestartSec = "10s";
        };
      };
    };
in
{

  systemd.user.services =
    lib.attrsets.mergeAttrsList [
      (rcloneService {
        name = "alist";
        REMOTE_NAME = "alist";
        REMOTE_PATH = "/";
        RCLONE_TEMP_DIR="${config.xdg.cacheHome}/rclone";
        RCLONE_MOUNT_DAEMON_TIMEOUT = "1h";
        RCLONE_MOUNT_VFS_CACHE_MAX_AGE = "4h";
        RCLONE_MOUNT_MULTI_THREAD_STREAMS = "0";
        RCLONE_MOUNT_TRANSFER = "4";
        RCLONE_MOUNT_VFS_CACHE_MODE = "full";
      })
      (rcloneService {
        name = "union-115";
        REMOTE_NAME = "union-115";
        REMOTE_PATH = "/";
        RCLONE_TEMP_DIR="${config.xdg.cacheHome}/rclone";
        RCLONE_MOUNT_DAEMON_TIMEOUT = "1h";
        RCLONE_MOUNT_MULTI_THREAD_STREAMS = "0";
        RCLONE_MOUNT_VFS_CACHE_MAX_AGE = "4h";
        RCLONE_MOUNT_TRANSFER = "6";
        RCLONE_MOUNT_VFS_CACHE_MODE = "full";
        RCLONE_MOUNT_TIMEOUT = "120m";
      })
      (rcloneService {
        name = "115-single";
        REMOTE_NAME = "encrypted-115-single";
        REMOTE_PATH = "/";
        RCLONE_TEMP_DIR="${config.xdg.cacheHome}/rclone";
        RCLONE_MOUNT_DAEMON_TIMEOUT = "1h";
        RCLONE_MOUNT_MULTI_THREAD_STREAMS = "0";
        RCLONE_MOUNT_TRANSFER = "4";
        RCLONE_MOUNT_VFS_CACHE_MODE = "full";
        RCLONE_MOUNT_TIMEOUT = "120m";
      })
      (rcloneService {
        name = "bk-meta";
        REMOTE_NAME = "115-onlyfilename";
        REMOTE_PATH = "/";
        RCLONE_TEMP_DIR="${config.xdg.cacheHome}/rclone";
        RCLONE_MOUNT_DAEMON_TIMEOUT = "1h";
        RCLONE_MOUNT_VFS_CACHE_MAX_AGE = "4h";
        RCLONE_MOUNT_MULTI_THREAD_STREAMS = "0";
        RCLONE_MOUNT_TRANSFER = "4";
        RCLONE_MOUNT_VFS_CACHE_MODE = "full";
        RCLONE_MOUNT_TIMEOUT = "120m";
      })
    ];
}
