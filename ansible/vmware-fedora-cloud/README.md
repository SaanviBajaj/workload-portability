# VMware Fedora Cloud Base track (MTV-friendly)

Builds two **Fedora 43** VMs from the official **Cloud Base Generic** QCOW2: customize with `virt-customize`, sparsify, convert to streamOptimized VMDK, deploy under **`Workload-Portability/`**, wire web ↔ db, expose the UI via the bastion.

| VM | Role |
|----|------|
| `todo-db` | PostgreSQL (`todo-db` container, host network, port 5432) |
| `todo-web` | Web UI (`todo-web` container, host network, 80→8080) |

**Run on the bastion.** Same VM names as Alpine/bootc — do not run tracks concurrently.

| Track | Guest | Typical provisioned size | Build time | MTV / virt-v2v |
|-------|-------|--------------------------|------------|----------------|
| `vmware-bootc` | CentOS Stream 9 bootc | **~1.7 GB** | Medium | Supported |
| `vmware-minimal` | Alpine | **~768 MB** | Fast | **Not** supported |
| **`vmware-fedora-cloud` (this)** | Fedora 43 Cloud Base | **~5 GiB** stock layout | **Faster** (no tar-repack) | **Supported** |

---

## Quick start

```bash
cd ansible/vmware-fedora-cloud
cp credentials.env.example credentials.env
# Edit govc_*, vm_network, vm_folder, govc_datastore

sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env
```

Cleanup:

```bash
sudo ansible-playbook cleanup-fedora-cloud-vms.yml -e @credentials.env
```

Bastion needs: `ansible`, `podman`, and `curl`.

`qemu-img` / `virt-customize` / `virt-sparsify` install via `dnf` when repos work; otherwise the playbook builds a local Podman image (`localhost/wp-fedora-cloud-guestfs:43`) and wrappers under `~/fedora-cloud-build/bin/`.

---

## What the build does

1. Downloads **Fedora-Cloud-Base-Generic-43** (cached under `~/fedora-cloud-build/cloud-images/`)
2. `virt-customize`: install `open-vm-tools`, `qemu-guest-agent`, `podman`; preload container image; enable systemd units; NM DHCP; disable cloud-init network config; volatile journald
3. `virt-sparsify --compress` (optional, default on) — reclaim unused blocks; **keeps stock GPT/btrfs layout**
4. Asserts MTV markers (`ID=fedora`, kernels, vmtools, `virt-inspector`)
5. Converts to **streamOptimized** VMDK → `govc` upload → `vm.create` (`fedora64Guest`, **UEFI**)
6. Discovers `todo-db` IP, bakes `DB_HOST` into the web image, deploys web, forwards bastion **:80** → web

Container images are **preloaded at build time**. Offline fallback: set `todo_db_image_tar` / `todo_web_image_tar` in `credentials.env`.

---

## Size: why ~5 GiB, and why we stopped shrinking

We tried tar-repacking Cloud Base down toward 768–2 GiB. That path was a bad fit:

| Approach | What happened |
|----------|----------------|
| Tar `/` to new ext4 disk | Btrfs **compressed** ~840 MiB → **uncompressed** ~1.6 GiB; + stock `/boot` overhead; **10+ min**; inspection breakage |
| `virt-resize` only | Stock **`/boot` is ~1–2 GiB** and is not the last partition, so you still floor near **~3 GiB** |
| **Keep stock Cloud Base (current)** | **~5 GiB provisioned**, stock layout MTV trusts, **much faster** |

**Datastore tip:** streamOptimized VMDK is sparse — **file size / used space** tracks written data (~1–2 GiB typical), even though vSphere shows **5 GiB capacity**.

If you need a **smaller provisioned** MTV-friendly disk, use **`ansible/vmware-bootc/`** (~1.7 GiB) instead of fighting Cloud Base.

**Not used:** Fedora CoreOS (~10 GiB), Anaconda Minimal ISO, custom `dnf --installroot`, or tar-repack.

### MTV checklist

- Guest OS type: **Fedora 64-bit** (`fedora64Guest`)
- Firmware: **UEFI**
- VMware Tools running (`open-vm-tools`)
- `/etc/os-release` has `ID=fedora`
- `/boot` has `vmlinuz-*` + initramfs
- Enough free space on `/` for virt-v2v (≥100 MB after first boot; volatile journald helps)

---

## credentials.env

Copy from `credentials.env.example`. Required:

- `govc_url`, `govc_username`, `govc_password`, `govc_datastore`
- `vm_network`, `vm_folder`

Optional: `db01_static_ip` / `web01_static_ip` / `db_host`; offline image tars; `-e fedora_sparsify=false` to skip sparsify.

---

## Tags

```bash
sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env --tags db01
sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env --tags web01
sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env --tags bastion-firewall
```

Cleanup tags: `vms`, `vmdks`, `bastion-firewall`, `local`.
