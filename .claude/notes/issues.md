# Known Issues

## Bugs

### 1. Syntax error in `kvm-import-image.sh` line 12
```bash
TMP_IMAGE_PATH===
```
Triple `=` is a syntax error. The variable gets reassigned by `mktemp` later so
it doesn't crash, but it prints an error and is misleading.
**Fix:** Change to `TMP_IMAGE_PATH=""` or just remove the line.

### 2. `kvm-create-vm.sh`: conflicting `--cdrom` and `--cloud-init` flags
`virt-install` is called with both `--cdrom ${TMP_CLOUD_INIT_SEED_FILE}` and
`--cloud-init user-data=...`. These two approaches overlap/conflict depending on
virt-install version. Typically you use one or the other.

### 3. `kvm-create-vm.sh` line 301: incomplete `--cloud-init` args
```bash
--cloud-init user-data=${TMP_CLOUD_INIT_USER_DATA_FILE} \
```
The `meta-data=` part is commented out on line 310. If `--cloud-init` is the
intended mechanism, it should include all three: `user-data`, `meta-data`, and
`network-config`.

### 4. `kvm-remote.sh`: assumes identical path on remote host
`install_utility_to_remote()` copies scripts to `$MYDIR` on the remote, where
`$MYDIR` is the local absolute path. If the remote has a different filesystem
layout this will fail silently or create unexpected directories.

### 5. `kvm-delete-vm.sh`: unused `ETHERNET_IFC_ON_IMAGE` array
The array is declared but never used in the script. Likely leftover from a copy-paste.

### 6. `kvm-create-vm.sh`: network-config only sets DHCP, not static IP
The cloud-init `network-config` enables DHCP on the interface:
```yaml
ethernets:
    enp1s0:
        dhcp4: true
```
The static IP is expected to come from libvirt's DHCP reservation (MAC→IP).
This is valid, but it means the VM won't have its intended IP if used without
the matching libvirt network, and the behaviour is not documented.

## Git Status Issues (untracked / uncommitted)

| File | Status |
|---|---|
| `kvm-create-vm.sh` | Modified (staged) |
| `kvm-import-image.sh` | Modified (unstaged) |
| `kvm-net.sh` | Modified (unstaged) |
| `kvm-remote.sh` | Modified (unstaged) |
| `kvm-install-webui.sh` | Untracked — not yet committed |
| `kvm-list.sh` | Untracked — not yet committed |
| `kvm-uninstall-webui.sh` | Untracked — not yet committed |

## Critical Bugs (found during in-progress investigation)

### 7. `kvm-net-define.sh` `main()`: uppercase/lowercase variable mismatch
`parse_args()` sets `$NETWORK_NAME`, `$BRIDGE_NAME`, `$NETWORK_CIDR` (uppercase).
`main()` uses `$network_name`, `$bridge_name`, `$network_cidr` (lowercase) — always empty.
Result: the idempotency check `grep -w "$network_name"` always passes (empty string matches
everything / nothing), and `generate_network_xml` is called with empty values.
**Script is effectively broken.**

### 8. `kvm-net-undefine.sh` `main()`: same uppercase/lowercase mismatch
Same problem — `main()` uses `$network_name` and `$bridge_name` (lowercase, always empty).
Neither the network destroy/undefine nor the bridge cleanup is reached properly.

### 9. `kvm-net-undefine.sh:84`: inverted condition for default bridge name
```bash
if [ "$BRIDGE_NAME" != "" ]; then      # BUG: should be ==
    BRIDGE_NAME="virbr${network_name}" # also uses wrong lowercase var
fi
```
When no `--bridge-name` is given, the condition is false so no default is set.
When one IS given, it gets overwritten with the (empty) default. Logic is backwards.

## Minor / Style

- `kvm-list.sh` help text says "List all KVM virtual machines on the specified
  remote server" but it only lists local VMs — misleading description.
- `kvm-net.sh` `redefine` action passes `"$1" "$2"` to undefine but passes all
  `"$@"` to define — potential argument mismatch if extra args are given.
- Error handling uses `if [ $? -ne 0 ]` style throughout instead of `||`
  — verbose but consistent.
