# kvm-utils Project Overview

## Purpose
Bash scripts to ease managing KVM/libvirt virtual machines.
Primarily targets RHEL-based systems (Rocky 9, CentOS, Fedora, AlmaLinux),
with partial Debian/Ubuntu support.

## File Map

| Script | Purpose |
|---|---|
| `kvm-include.sh` | Shared library: logging, OS detection, MAC/bridge/network helpers |
| `kvm-install.sh` | Install KVM + libvirt |
| `kvm-uninstall.sh` | Uninstall KVM + libvirt |
| `kvm-install-webui.sh` | Install Cockpit WebUI (cockpit-machines) — untracked |
| `kvm-uninstall-webui.sh` | Uninstall Cockpit WebUI — untracked |
| `kvm-net.sh` | Dispatcher: define / undefine / redefine / list networks |
| `kvm-net-define.sh` | Create NAT bridge network with static DHCP |
| `kvm-net-undefine.sh` | Remove a libvirt network |
| `kvm-import-image.sh` | Download + convert cloud images (14 distros known) |
| `kvm-create-vm.sh` | Create VM via cloud-init (user-data, network-config, meta-data) |
| `kvm-delete-vm.sh` | Stop + undefine VM + delete its volume |
| `kvm-list.sh` | List all VMs (virsh list --all) — untracked |
| `kvm-remote.sh` | SCP scripts to remote host and execute via SSH |
| `test/test-include.sh` | Tests for kvm-include.sh functions |

## Key Design Patterns
- All scripts source `kvm-include.sh` for shared helpers.
- Idempotent where stated (install, net-define, net-undefine).
- Static IP assignment done via libvirt DHCP reservation (MAC→IP), not cloud-init static config.
- MAC address derived deterministically from IP: `ip_to_mac()` in kvm-include.sh.
- `kvm-remote.sh` assumes the same absolute `$MYDIR` path exists on the remote host.
