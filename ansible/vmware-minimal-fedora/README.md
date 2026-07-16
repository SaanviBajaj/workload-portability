# VMware Minimal Fedora VM Build

Builds the same **todo-db** / **todo-web** demo as the Alpine track, but with a **Fedora** guest OS so MTV / OpenShift Virtualization can convert the VMs.

| | Alpine (`vmware-minimal`) | **Fedora (this guide)** |
|---|---|---|
| Guest OS | Alpine Linux | Fedora 40 |
| MTV / virt-v2v | **Not supported** | **Supported** |
| Disk size | ~768 MB | **~1.1 GiB** |
| Init | OpenRC | systemd-networkd |
| Networking | ifupdown + DHCP | systemd-networkd |

**Size tricks:** no firmware packages, `kernel-core` + `kernel-modules` only (GPU/media/sound modules stripped), systemd-networkd instead of NetworkManager, docs/locales removed after install.

Fedora + Podman still needs ~560 MiB for the OS install alone, so disks cannot match Alpine’s 768 MB. **1152 MB** is the practical minimum for this track (1024 MB leaves too little free space after first boot for MTV).

The image is built to look like a normal Fedora installation for `virt-v2v` inspection: Fedora release identity packages are installed explicitly, `kernel-install` + `dracut` populate `/boot`, and the playbook verifies `/etc/os-release`, RPM metadata, `vmlinuz`, and `initramfs` before upload.

If MTV still shows **Unsupported operating system detected**, confirm in vSphere that the VM **Guest OS** is **Fedora (64-bit)** / `fedora64Guest`, not `Other Linux`. The deploy playbook sets this on create and updates it on existing VMs.

**Do not run this track and Alpine/bootc at the same time** — they use the same VM names (`todo-db`, `todo-web`).

Run everything on your **bastion VM**.

---

## Quick start

```bash
cd ~/workload-portability/ansible/vmware-minimal-fedora
cp credentials.env.example credentials.env
# edit credentials.env with your sandbox values

sudo ansible-playbook build-fedora-minimal-vms.yml -e @credentials.env
```

Cleanup Alpine VMs first if they still exist:

```bash
cd ../vmware-minimal
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
```

---

## What you get

| VM | Role |
|----|------|
| `todo-db` | Preloaded PostgreSQL container (`--network host`, port 5432) |
| `todo-web` | Preloaded web app + SSH (`demo` / `demo`), HTTP 80→8080 |

### Sizing defaults

- 2 vCPU, 4 GiB RAM, BIOS, SCSI
- Guest ID: `fedora64Guest`
- Disk: **1152 MB** (~1.1 GiB; build checks ≥200 MB free; MTV needs ≥100 MB after first boot)

If the build fails with “needs more space” during dnf or “only X MB free on `/`”, bump `disk_mb` to `1280` or `1536`.

### MTV free-space gotcha

The playbook measures `/` at **image build time**. After the VM boots, Podman (container overlay under `/var/lib/containers`) and systemd logs consume **~50–70 MB** more. MTV/virt-v2v checks the **running** guest, so a build that reports 144 MB free can still fail migration with 83 MB free. Defaults now use a larger disk and `fedora_min_free_mb: 200` to leave headroom.

---

## Credentials

Same shape as the Alpine track — copy `credentials.env.example` → `credentials.env`. Bastion prerequisites: see [`../vmware-minimal/README-SETUP.md`](../vmware-minimal/README-SETUP.md).

---

## Partial runs

```bash
sudo ansible-playbook build-fedora-minimal-vms.yml -e @credentials.env --tags db01
sudo ansible-playbook build-fedora-minimal-vms.yml -e @credentials.env --tags web01
sudo ansible-playbook build-fedora-minimal-vms.yml -e @credentials.env --tags bastion-firewall
```

---

## Cleanup

```bash
sudo ansible-playbook cleanup-fedora-minimal-vms.yml -e @credentials.env
```

---

## MTV tip

Power off the VMs in vSphere before migrating. Use your VDDK-backed provider. Migrate one VM first if conversions were previously hanging.
