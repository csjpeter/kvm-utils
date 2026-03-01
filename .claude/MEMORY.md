# Claude Memory — kvm-utils Project

## Notes Index
- `notes/project-overview.md` — file map, design patterns, architecture
- `notes/issues.md` — bugs, git status issues, style notes

## Quick Facts
- Primary target OS: RHEL-family (Rocky 9, CentOS, Fedora, AlmaLinux)
- Shared helpers in `kvm-include.sh` (logging, OS detection, MAC/bridge/network lookup)
- Static IP via libvirt DHCP reservation using MAC derived from IP (`ip_to_mac()`)
- `kvm-remote.sh` requires same absolute path on remote host
- WebUI scripts (cockpit) and kvm-list.sh are new, not yet committed

## Open Issues (summary — see notes/issues.md for details)
1. `kvm-import-image.sh:12` — `TMP_IMAGE_PATH===` syntax error
2. `kvm-create-vm.sh` — conflicting `--cdrom` + `--cloud-init` flags
3. `kvm-create-vm.sh` — incomplete `--cloud-init` args (meta-data commented out)
4. `kvm-remote.sh` — assumes same `$MYDIR` path on remote
5. `kvm-delete-vm.sh` — unused `ETHERNET_IFC_ON_IMAGE` array
6. `kvm-list.sh` — misleading help text says "remote server"
7. `kvm-net-define.sh` `main()` — uppercase/lowercase var mismatch; script is broken
8. `kvm-net-undefine.sh` `main()` — same uppercase/lowercase var mismatch; script is broken
9. `kvm-net-undefine.sh:84` — inverted condition for default bridge name
