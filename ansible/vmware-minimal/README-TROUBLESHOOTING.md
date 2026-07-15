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
| `no space left on device` during `Load container image` | Disk too tight for chroot `podman load` (tar + image + temp) | `git pull` — build bind-mounts the tar from bastion and uses bastion `/tmp` for scratch space; default `disk_mb` is now 768 |
| Build fails: `need at least 100 MB` for migration | Rootfs too full after image preload | Increase `disk_mb` or shrink container images; default is 768 MB |
| MTV / OpenShift Virt: `Insufficient free space for conversion on '/'` | Guest `/` has &lt; 100 MB free (common with old 600 MB disks) | Rebuild with `git pull` (`disk_mb: 768`) and re-run migration validation |
| `database configuration mismatch` / `podman-preload/libpod` | Podman storage copied from bastion retained wrong paths | `git pull` and rebuild — image is loaded inside the Alpine chroot so paths match `/var/lib/containers/storage` |

On a running VM, try manually on the **todo-db console**:

```sh
mount -o remount,rw /
sudo rc-service todo-db restart
sudo podman ps -a
```

---

## OpenShift Virtualization / MTV migration — insufficient free space on `/`

Migration validation requires **at least 100 MB free** on the guest root filesystem for conversion scratch space.

The playbook now defaults to **`disk_mb: 768`** and **fails the build** if free space on `/` would be below **`alpine_min_free_mb: 100`** after the image is preloaded.

If you still see this on VMs built before that change:

```bash
cd ~/workload-portability/ansible/vmware-minimal
git pull
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

Verify on the **todo-db console** before migrating:

```sh
df -h /
# Avail on / should be ≥ 100 MB
```

Override the minimum if your migration tooling changes requirements:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env -e alpine_min_free_mb=150
```


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

## `govc vm.destroy` — Device or resource busy

`vm.destroy` failed because VMware still has a lock on the VM. Common causes:

1. **OpenShift MTV migration plan** is attached — cancel or delete the plan in the MTV UI first
2. VM is **still powered on** or **still shutting down** — wait 30–60s after power off
3. A **snapshot** or backup job holds the disk

**Fix now (on bastion, without git pull):**

```bash
# Hard power off and wait
sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.power -off -wait=true todo-web

# Retry destroy after a minute
sleep 60
sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.destroy todo-web
```

If you were migrating to OpenShift Virtualization, **delete the MigrationPlan** (or cancel an in-progress migration) in the OpenShift console, then retry cleanup.

After `git pull`, the cleanup playbook waits for power-off and retries destroy automatically.

---

## VMDK shows as "Locked" in vSphere

A previous upload may have left a stuck lock. Run cleanup, then re-run:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vmdks
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags db01
```

---

## `vm.create` — Invalid configuration for device '1'

Older playbook versions used `datastore.upload` and attached the disk with `vm.create -disk`, which often fails on VMFS. Current builds use `govc import.vmdk` (requires a `streamOptimized` VMDK) and then `vm.create -disk` against the imported path.

**Fix:** `git pull` and rebuild:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vms
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

---

## `datastore.mv` — VMDK already exists

The build uploads to `Workload-Portability/todo-db-disk1.vmdk` then moves to `Workload-Portability/todo-db/todo-db-disk1.vmdk`. A **failed or partial cleanup** leaves the subfolder copy behind, so the move fails with **already exists**.

**Fix now (bastion):**

```bash
GOVC="sudo podman run --rm --env-file /root/minimal-build/govc.env docker.io/vmware/govc:latest /govc"

$GOVC datastore.rm Workload-Portability/todo-db/todo-db-disk1.vmdk
$GOVC datastore.rm Workload-Portability/todo-db-disk1.vmdk
$GOVC datastore.rm Workload-Portability/todo-db
```

Then re-run the build. After `git pull`, the playbook removes stale VMDKs before upload/move automatically.

See also [README-CLEANUP.md](README-CLEANUP.md) for full manual datastore cleanup.

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
