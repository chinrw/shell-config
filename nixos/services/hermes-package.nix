{ lib, package }:
package.override (args: {
  pmPackages = lib.mapAttrs (
    _: tool:
    tool.overrideAttrs (toolAttrs: {
      nativeBuildInputs = map (
        dependency:
        # Hermes' header-overlap patch targets patchelf 0.19.x, but nixpkgs
        # also supplies 0.15.2, whose source cannot accept that patch.
        if (dependency.pname or "") == "patchelf" && lib.versionOlder dependency.version "0.19" then
          dependency.overrideAttrs (attrs: {
            patches = builtins.filter (
              patch: !lib.hasSuffix "-patchelf-fix-executable-header-load-overlap.patch" (toString patch)
            ) (attrs.patches or [ ]);
          })
        else
          dependency
      ) toolAttrs.nativeBuildInputs;
    })
  ) args.pmPackages;
})
