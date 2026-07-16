# VMware Fedora Cloud Base track (MTV-friendly)

Builds two **Fedora 43** VMs from the official **Cloud Base Generic** QCOW2, customizes them with `virt-customize`, repacks each disk to **`disk_mb` (default 1536)**, uploads streamOptimized VMDKs under **`Workload-Portability/`**, and wires the todo demo so web ↔ db talk and the UI is reachable via the bastion.

| VM | Role |
|----|------|
| `todo-db` | PostgreSQL (`todo-db` container, host network, port 5432) |
| `todo-web` | Web UI (`todo-web` container, host network, 80→8080) |

**Run on the bastion.** Same VM names as Alpine/bootc — do not run tracks concurrently.

| Track | Guest | Typical provisioned size | MTV / virt-v2v |
|-------|-------|--------------------------|----------------|
| `vmware-bootc` | CentOS Stream 9 bootc | ~1.7 GB | Supported |
| `vmware-minimal` | Alpine | ~768 MB | **Not** supported |
| **`vmware-fedora-cloud` (this)** | Fedora 43 Cloud Base | **~1.5 GiB** provisioned (see size notes) | **Supported** (`fedora64Guest`) |

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

`qemu-img` / `virt-customize` (guestfs) are installed via `dnf` when repos work; otherwise the playbook **builds a local Podman image** (`localhost/wp-fedora-cloud-guestfs:43`) and uses wrappers under `~/fedora-cloud-build/bin/`. First run may take several minutes to pull Fedora and install packages in that image.

---

## What the build does

1. Downloads **Fedora-Cloud-Base-Generic-43** (cached under `~/fedora-cloud-build/cloud-images/`)
2. `virt-customize`: install `open-vm-tools`, `qemu-guest-agent`, `podman`; preload container image; enable systemd units; NM DHCP; disable cloud-init network config; volatile journald
3. **Repacks** to a UEFI GPT disk of size `disk_mb` (ESP + `/boot` + `/` as ext4) — stock Cloud Base is **5 GiB** virtual with a **~1 GiB `/boot`**, so a plain `virt-resize` cannot hit 768 MB
4. Asserts MTV markers (`ID=fedora`, kernels under `/boot`, vmtools present, free space ≥ `fedora_min_free_mb`)
5. Converts to **streamOptimized** VMDK → `govc` upload → `vm.create` (`fedora64Guest`, **UEFI**)
6. Discovers `todo-db` IP, bakes `DB_HOST` into the web image, deploys web, forwards bastion **:80** → web

Container images are **preloaded at build time** (quay pulls at first boot are unreliable in the lab). Offline fallback: set `todo_db_image_tar` / `todo_web_image_tar` in `credentials.env`.

---

## Size and MTV notes

| Variable | Default | Meaning |
|----------|---------|---------|
| `disk_mb` | `1536` | Provisioned disk target after repack |
| `fedora_min_free_mb` | `150` | Build-time free space on `/` (MTV needs ≥100 MB **after** first boot) |
| `disk_mb_max` | `2048` | Hard ceiling — build refuses to go higher unless you raise this |

Measured on a customized Cloud Base image: root is typically **~840+ MiB used** (OS + podman + preloaded container). That cannot fit in 768 or 1024 after EFI/`/boot` overhead and MTV free-space headroom — hence the **1536** default.

If OS + preloaded image still cannot fit, the repack step **fails with measured sizes** and suggests a larger `disk_mb` (up to `disk_mb_max`). It will **not** silently invent another custom rootfs.

**600–768 MB** remains aspirational and is not achievable with stock Cloud Base + preloaded images.

**Not used (by design):** Fedora CoreOS (~10 GiB), Anaconda Minimal ISO, or the scrapped `dnf --installroot` track.

### MTV checklist

- Guest OS type: **Fedora 64-bit** (`fedora64Guest`)
- Firmware: **UEFI**
- VMware Tools running (`open-vm-tools`)
- `/etc/os-release` has `ID=fedora`
- `/boot` has `vmlinuz-*` + initramfs
- ≥100 MB free on `/` when MTV inspects the disk (we reserve 150 MB at build + volatile journal)

---

## credentials.env

Copy from `credentials.env.example`. Required:

- `govc_url`, `govc_username`, `govc_password`, `govc_datastore`
- `vm_network`, `vm_folder`

Optional: `db01_static_ip` / `web01_static_ip` / `db_host` if Tools IP discovery fails; offline image tars.

---

## Tags

```bash
sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env --tags db01
sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env --tags web01
sudo ansible-playbook build-fedora-cloud-vms.yml -e @credentials.env --tags bastion-firewall
```

Cleanup tags: `vms`, `vmdks`, `bastion-firewall`, `local`.
