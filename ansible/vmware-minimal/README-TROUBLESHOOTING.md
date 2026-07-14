# VMware Minimal — Troubleshooting

**Main guide:** [README.md](README.md)

---

## Recommended first step

Always pull the latest playbook fixes, then do a clean rebuild:

```bash
cd ~/workload-portability/ansible/vmware-minimal
git pull
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

If quay.io denies pulls during build, copy offline image tars first (see [Offline container images](README.md#offline-container-images-when-quayio-denies-pulls) in the main guide).

---

## "Permission denied" or Podman errors

Make sure you're using `sudo`:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

---

## `No package qemu-img available` or `no enabled repositories`

Lab bastions often have **no dnf repos** — you cannot install packages with `dnf`. That's expected.

The playbook handles this by running `qemu-img` inside a Podman container (Alpine image with internet access). Just `git pull` and re-run:

```bash
cd ~/workload-portability/ansible/vmware-minimal
git pull
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

Quick test that the Podman fallback works:

```bash
sudo podman run --rm docker.io/library/alpine:3.20 \
  sh -ec "apk add --no-cache qemu-img && qemu-img --version"
```

If that fails, the bastion cannot reach the internet to pull container images.

---

## Playbook hangs waiting for VM IP

`govc vm.ip` needs **open-vm-tools** running inside the guest. First boot can take a minute or two before the IP appears.

1. Check the VM console in vSphere — did Alpine boot? Look for `[ ok ] Starting todo-db container`
2. Wait longer per attempt: `-e vm_ip_wait=90s` or more retries: `-e vm_ip_retries=30`
3. Or set static IPs in `credentials.env` to skip discovery:

```yaml
db01_static_ip: "192.168.x.x"
web01_static_ip: "192.168.x.x"
```

---

## `todo-db failed to start` on VM console

Common causes and fixes:

| Console message | Cause | Fix |
|-----------------|-------|-----|
| `eth0: No such device` / `ifup failed` | VMware NIC not ready at boot | `git pull` and rebuild (network-wait fix) |
| `Read-only file system` | Root disk not remounted rw | `git pull` and rebuild (OpenRC `root` service fix) |
| `podman pull failed` | quay.io denied or no internet on VM | `git pull` and rebuild (images preloaded at build time) |
| `container image missing from VMDK` | VMDK built without preloaded image | Rebuild with `build-minimal-vms.yml` |
| `no space left on device` during `Load container image` | 600 MB disk too tight for chroot `podman load` (tar + image + temp) | `git pull` — build bind-mounts the tar from bastion and uses bastion `/tmp` for scratch space |
| `database configuration mismatch` / `podman-preload/libpod` | Podman storage copied from bastion retained wrong paths | `git pull` and rebuild — image is loaded inside the Alpine chroot so paths match `/var/lib/containers/storage` |

On a running VM, try manually on the **todo-db console**:

```sh
mount -o remount,rw /
sudo rc-service todo-db restart
sudo podman ps -a
```

---

## quay.io denies pulls (build time)

VMs **must not** pull from quay.io at runtime. Images are preloaded into Podman storage during the bastion build.

If the bastion also cannot pull, use [offline image tars](README.md#offline-container-images-when-quayio-denies-pulls).

---

## Web app loads but can't reach the database

The web image was built with a **stale `DB_HOST`** (DHCP gave todo-db a different IP after rebuild). Rebuild **both** VMs together, or rebuild web with the current DB IP:

```bash
DB_IP=$(sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-db)

sudo ansible-playbook build-minimal-vms.yml -e @credentials.env \
  -e db_host=$DB_IP \
  --tags web01
```

On a running **todo-web** VM, you can also fix without rebuild:

```sh
sudo podman stop todo-web && sudo podman rm todo-web
sudo podman run -d --name todo-web --network host \
  -e DB_HOST=<current-todo-db-ip> \
  -e DB_PORT=5432 \
  quay.io/rh-ee-sbajaj/todo-web:latest
sudo iptables -t nat -A PREROUTING -p tcp --dport 80 -j REDIRECT --to-ports 8080
```

---

## `ss: not found` on todo-web

Harmless. The startup script tries to list open ports with `ss`, which is not installed on minimal Alpine. The container still starts — ignore this message if `podman ps` shows `todo-web` as **Up**.

---

## `govc.env` not found

When you run with `sudo`, the file is at `/root/minimal-build/govc.env` (not your home directory):

```bash
sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web
```

---

## VMDK shows as "Locked" in vSphere

A previous upload may have left a stuck lock. Run cleanup, then re-run:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vmdks
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags db01
```

---

## VMs already exist from a previous run

Either destroy them first:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vms
```

Or delete them manually in vSphere, then re-run the build playbook.

---

## Browser URL doesn't load

Work through this list in order:

1. **Internal test first:** `curl -I http://<todo-web-ip>` from bastion — do you get `HTTP/1.1 200`?
2. **DB port open:** `timeout 3 bash -c "echo >/dev/tcp/<todo-db-ip>/5432"` — must succeed
3. **Firewall rule:** `sudo firewall-cmd --list-forward-ports` — does `toaddr` match the **current** todo-web IP?
4. **Re-apply firewall** if the VM IP changed (DHCP):

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags bastion-firewall
```

5. **Don't run nginx on the bastion** on port 80 — it fights with `firewalld` forwarding.

---

## Conflicts with bootc track

Both tracks use VM names `todo-db` and `todo-web`. If you switched tracks, clean up the old one first — see [README-CLEANUP.md](README-CLEANUP.md).
