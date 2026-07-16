# VMware Minimal Fedora VM Build

Builds the same **todo-db** / **todo-web** demo as the Alpine track, but with a **Fedora** guest OS so MTV / OpenShift Virtualization can convert the VMs.

| | Alpine (`vmware-minimal`) | **Fedora (this guide)** |
|---|---|---|
| Guest OS | Alpine Linux | Fedora 41 |
| MTV / virt-v2v | **Not supported** | **Supported** |
| Disk size | ~768 MB | **~1 GiB** |
| Init | OpenRC | systemd-networkd |
| Networking | ifupdown + DHCP | systemd-networkd |

**Size tricks:** no firmware packages, `kernel-core` + `kernel-modules` only (GPU/media/sound modules stripped), systemd-networkd instead of NetworkManager, docs/locales removed after install.

Fedora + Podman still needs ~560 MiB for the OS install alone, so disks cannot match Alpine’s 768 MB. **1 GiB (1024 MB)** is the practical minimum for this track.

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
- Disk: **1024 MB** (~1 GiB; needs ≥100 MB free for MTV)

If the build fails with “needs more space” during dnf or “only X MB free on `/`”, bump `disk_mb` to `1280` or `1536`.

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
