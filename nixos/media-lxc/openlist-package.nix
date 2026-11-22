{ pkgs }:
pkgs.openlist.overrideAttrs (old: {
  patches = (old.patches or [ ]) ++ [ ./openlist-115-status.patch ];
  doCheck = false;
  postConfigure = (old.postConfigure or "") + ''
    go mod vendor
    patch -p1 < ${./openlist-115-progress.patch}
    export GOFLAGS="$GOFLAGS -mod=vendor"
  '';
})
