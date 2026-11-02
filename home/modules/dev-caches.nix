{ ... }:

# Build intermediates go to one central, non-snapshotted place instead of each
# project's ./target (mantle had 19.6 GB of target/ dirs pinned in snapshots).
# build-dir (stable since Cargo 1.91) keeps them per project via the path hash,
# so projects don't share a build lock; final binaries stay in ./target.
# ~/.cargo is its own btrfs subvolume where diskHygiene.subvolumes lists it.
{
  home.file.".cargo/config.toml".text = ''
    [build]
    build-dir = "{cargo-cache-home}/build/{workspace-path-hash}"
  '';
}
