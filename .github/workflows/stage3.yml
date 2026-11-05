name: stage3
on: workflow_dispatch
jobs:
  build:
    runs-on: ubuntu-24.04-arm
    timeout-minutes: 340
    env:
      LFS: /mnt/lfs
      GH_TOKEN: ${{ github.token }}
    steps:
      - uses: actions/checkout@v4
      - name: Free disk space
        run: |
          sudo rm -rf /usr/share/dotnet /opt/ghc /usr/local/lib/android
          df -h /
      - name: Host setup
        run: bash scripts/00-host-setup.sh
      - name: Restore stage2
        run: |
          gh release download stage2 -p stage2.tar.zst
          sudo tar --zstd -xpf stage2.tar.zst -C $LFS
          sudo chown -R $(id -u):$(id -g) $LFS
          rm stage2.tar.zst
          mkdir -p $LFS/sources logs
      - name: Download missing sources
        run: bash scripts/01-sources.sh
      - name: Chroot Setup & Build
        run: sudo bash scripts/04-chroot-setup.sh
      - name: Unmount & Cleanup
        run: sudo bash scripts/06-unmount.sh
      - name: Pack
        run: sudo tar -C $LFS --exclude=./sources -I 'zstd -T0 -12' -cf stage3.tar.zst .
      - uses: actions/upload-artifact@v4
        if: always()
        with: { name: stage3-logs, path: logs/ }
      - uses: softprops/action-gh-release@v2
        with: { tag_name: stage3, files: stage3.tar.zst }
