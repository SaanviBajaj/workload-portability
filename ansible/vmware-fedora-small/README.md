# VMware Fedora-small track (native app, MTV-friendly)

Builds **one ~1.7 GiB Fedora 43 Cloud Base golden** using the [grantomation `fedora-small`](https://github.com/grantomation/wandering-workload-demo/blob/master/ansible/golden-images/fedora-small.yml) method (btrfs pre-shrink + `virt-resize`, **no Podman**), deploys **`todo-db` / `todo-web`**, then installs [SaanviBajaj/to-do-app](https://github.com/SaanviBajaj/to-do-app) **natively** (PostgreSQL + Node).

| VM | Role |
|----|------|
| `todo-db` | Native PostgreSQL, database `todo`, table `todos` |
| `todo-web` | Native Node (`server.js`), `DB_HOST=todo-db-svc` |

**Run on the bastion** (and configure playbooks **on each guest**). Same VM names as other tracks — do not run tracks concurrently.

| Track | Guest | Disk | MTV |
|-------|-------|------|-----|
| `vmware-minimal` | Alpine + Podman | ~768 MB | Not supported |
| `vmware-fedora-cloud` | Fedora + Podman preload | ~2.3 GiB+ | Supported (heavier) |
| **`vmware-fedora-small` (this)** | Fedora + native app | **~1.7 GiB** | **Supported** (raw copy) |

---

## Quick start

```bash
cd ansible/vmware-fedora-small
cp credentials.env.example credentials.env
# Edit govc_*, vm_network, vm_folder, and set static IPs / gateway for your sandbox

# 1) Build golden (~1740M virtual disk)
sudo ansible-playbook golden/fedora-small.yml -e @credentials.env

# 2) Upload VMDK, create todo-db, clone todo-web, discover IPs, configure guests
sudo ansible-playbook deploy-fedora-small-vms.yml -e @credentials.env
```

Deploy uses `govc vm.ip` to find guest IPs, then SSHs in (`fedora` / `openshift`) and runs the `vm-configure` playbooks automatically (`auto_configure_guests: true`).

Skip auto-configure: `-e auto_configure_guests=false` (then run the guest playbooks yourself).

Optional static IPs in `credentials.env` (`db01_static_ip` / `web01_static_ip`) pin addresses; otherwise guests keep DHCP and only get `todo_db_ip` for env-detect.

Verify:

```bash
curl http://<web-ip>:8080/health
# or via bastion :80 forward after deploy
curl http://<bastion>/health
```

Cleanup:

```bash
sudo ansible-playbook cleanup-fedora-small-vms.yml -e @credentials.env
```

---

## How the golden is built

1. Download **Fedora-Cloud-Base-Generic-43**
2. `virt-customize`: `qemu-guest-agent`, `open-vm-tools`, `ansible-core`, `acl`; bake `/home/fedora/to-do-app` + `/home/fedora/vm-configure`
3. `virt-sysprep` + `virt-sparsify`
4. **Btrfs dance:** `guestfish btrfs-filesystem-resize` → `1600M`, then `virt-resize --shrink` into **`1740M`** disk
5. Convert to **streamOptimized** VMDK

Do **not** lower `btrfs_size` / `target_size` without re-probing (grantomation floor).

Bastion needs `ansible`, `podman`, `git`, `rsync`, `curl`. Guestfs tools install via `dnf` when possible; otherwise a local Podman guestfs image + wrappers under `~/fedora-small-build/bin/`.

---

## Networking (VMware → OpenShift)

App always uses **`DB_HOST=todo-db-svc`**. Do **not** preserve VMware IPs after MTV.

| Platform | Resolver |
|----------|----------|
| VMware | `todo-env-detect` writes `/etc/hosts`: `todo-db-svc` → `todo_db_ip` |
| OpenShift Virt | env-detect clears the VMware hosts block and points the guest at **cluster CoreDNS** (`CLUSTER_DNS_IP`, default `172.30.0.10`) with search domains so `todo-db-svc` resolves to the Service |

Optional fallback if CoreDNS still is not reachable inside the guest: set `TODO_DB_SERVICE_IP=<ClusterIP>` in `/etc/todo-workload.env` and restart `todo-env-detect` (prep script prints the ClusterIP).

### MTV prep (before Start)

```bash
oc login ...
./scripts/prep-mtv-2tier.sh
```

Creates project (default `portable-workload`), Services `todo-db-svc` / `todo-web-svc`, and Route `todo-web`.

Plan settings:

- Cold migration
- **`skipGuestConversion: true`** (raw copy — proven path for this guest)
- StorageClass that actually binds for CDI (avoid WFFC-only traps that leave PVCs Pending)

After migrate:

```bash
oc get vmi,endpoints -n portable-workload
oc get route todo-web -n portable-workload
```

---

## Size notes

| Variable | Default | Meaning |
|----------|---------|---------|
| `btrfs_size` | `1600M` | Pre-shrink btrfs (no balance) |
| `target_size` | `1740M` | Final disk geometry |
| `vmdk_subformat` | `streamOptimized` | govc-friendly upload |

This is **not** a 600/768 MB track. Native Postgres/Node stays within the ~1.7 GiB floor; Podman+preload does not.

---

## Credentials

See `credentials.env.example`. Required: `govc_*`, `vm_network`, `vm_folder`.

Recommended for configure: `todo_db_ip` / `db01_static_ip`, `web01_static_ip`, `net_gateway`, `net_dns`.

Optional: `app_src` pointing at a local [to-do-app](https://github.com/SaanviBajaj/to-do-app) checkout (skips git clone during golden build).
