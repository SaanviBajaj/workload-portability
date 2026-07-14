# VMware Minimal VM Build — Step-by-Step Guide

This playbook builds and deploys two **small** VMs for the todo app demo:

| VM name (default) | What it does |
|-------------------|--------------|
| `todo-db` | Database (PostgreSQL) |
| `todo-web` | Web app (the page you open in a browser) |

**Run everything on your bastion VM** — the Linux VM in your demo environment that can talk to VMware.

This is the **minimal** track. It makes **smaller disk images** than the bootc track (~1 GB vs ~1.7 GB per VM).

**Important:** Container images are **preloaded into Podman storage at build time** on the bastion (no `.tar` left on disk). The VMs do **not** pull from quay.io at boot (quay.io often denies pulls in lab environments).

**Need to copy these files onto the bastion first?** → See [Getting files onto the bastion](#step-1--get-the-files-onto-the-bastion) below (or use the same copy methods as [../vmware-bootc/README-BASTION.md](../vmware-bootc/README-BASTION.md) — just use the `vmware-minimal` folder instead of `vmware-bootc`).

**Need to tear down VMs and clean up?** → See [Cleanup when you're done](#cleanup-when-youre-done).

---

## What is this, in plain English?

Imagine you want two virtual computers in VMware:

1. One runs the **database** (stores your todo items)
2. One runs the **website** (shows the todo list in your browser)

Normally you'd install an OS, install Docker/Podman, configure networking, upload disks… this playbook does all of that for you automatically.

### How is "minimal" different from "bootc"?

| | Bootc track (`vmware-bootc`) | **Minimal track (this guide)** |
|---|------------------------------|--------------------------------|
| OS inside the VM | Full CentOS Stream 9 bootc image | Tiny Alpine Linux |
| Disk size | ~1.7 GB per VM | **~1 GB per VM** (preloaded container images) |
| Good when | You want a "real" RHEL-like VM | You want small disks for demos/migration |

Both tracks create the **same VM names** (`todo-db`, `todo-web`). **Do not run both at the same time** — pick one track.

If you already deployed the bootc VMs, clean them up first:

```bash
cd ~/workload-portability/ansible/vmware-bootc
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env
```

---

## Before you start

You need to be logged into the **bastion VM** (not your laptop) for all the commands below.

### Check these tools exist

```bash
ansible-playbook --version
podman --version
which losetup sfdisk mkfs.ext4 mount
```

The playbook needs **podman** plus basic Linux tools (`losetup`, `sfdisk`, `mkfs.ext4`, `mount`). These are usually pre-installed on the bastion.

`qemu-img` is **not** required on the host — if it's missing (common on lab bastions with no dnf repos), the playbook runs it via Podman automatically.

Optional manual check:

```bash
qemu-img --version    # OK if this works; OK if it doesn't too
```

### Information you need from the demo environment

| What | Example | Where to find it |
|------|---------|------------------|
| **Sandbox ID** | `vn5tw` | Your sandbox name (the `XXXXX` part) |
| **vCenter password** | (your password) | Demo credentials |
| **Bastion access** | `ssh demo@<bastion-ip>` | Demo environment |

### Important VMware rule

Your VMs must be created inside:

```
Workloads/sandbox-XXXXX
```

If they land somewhere else, you won't see them in your sandbox UI. The playbook handles this via `vm_folder` in your credentials file.

---

## What the playbook actually builds

### The disk image (VMDK)

Each VM boots from a **VMDK file** — think of it as a virtual hard drive you upload to VMware.

| VM | Build output on bastion | Size (approx.) |
|----|-------------------------|----------------|
| `todo-db` | `todo-db/output/disk.vmdk` | **~800 MB–1 GB** |
| `todo-web` | `todo-web/output/disk.vmdk` | **~800 MB–1 GB** |

The playbook builds these on the bastion using:

- **Alpine Linux** — a very small Linux distro (not a full CentOS install)
- **Podman** — runs the actual todo app containers inside the VM
- **Preloaded container images** — `todo-db` / `todo-web` images are loaded into Podman storage during the bastion build (tar archives are deleted)
- **qemu-img** — creates and converts the virtual disk

### What's inside each VM?

**todo-db VM:**
- Tiny Alpine Linux (just enough to boot and run Podman)
- On startup, runs the preloaded `todo-db` image from local Podman storage (PostgreSQL on port **5432**)
- Uses **host networking** (`--network host`) — no bridge/port-map setup needed
- No SSH login — use the **vSphere web console** for troubleshooting

**todo-web VM:**
- Tiny Alpine Linux + SSH (user `demo` / password `demo`)
- On startup, runs the preloaded `todo-web` image from local Podman storage
- Runs the web app on port **8080** with **host networking**, and redirects incoming port **80 → 8080** via iptables
- `DB_HOST` is **baked into the disk at build time** — the playbook discovers todo-db's IP before building the web image

### VM sizing (defaults)

- **2 vCPU**
- **4 GB RAM**
- **BIOS** firmware (not UEFI)
- **SCSI** disk controller

### The three Ansible "roles" (building blocks)

You don't need to run these separately — the main playbook calls them for you. But it helps to know what they do:

| Role | What it does (plain English) |
|------|------------------------------|
| `alpine-vmdk` | Builds the small Alpine disk image on the bastion |
| `vmware-vm` | Uploads the disk to VMware and creates the VM |
| `bastion-firewall` | Sets up port forwarding so your **laptop browser** can reach the web app |

---

## Step 1 — Get the files onto the bastion

SSH into your bastion:

```bash
ssh BASTION_USER@BASTION_HOST
```

### Option A — Git pull (easiest if repo is on GitHub)

```bash
cd ~/workload-portability
git pull
cd ansible/vmware-minimal
```

First time cloning?

```bash
git clone https://github.com/SaanviBajaj/workload-portability.git
cd workload-portability/ansible/vmware-minimal
```

### Option B — Copy from your laptop with scp

On your **laptop**:

```bash
scp -r ~/Desktop/workload-portability/ansible/vmware-minimal \
  BASTION_USER@BASTION_HOST:~/workload-portability/ansible/
```

On the **bastion**:

```bash
cd ~/workload-portability/ansible/vmware-minimal
ls build-minimal-vms.yml credentials.env.example README.md
```

More copy options (rsync, tar, etc.) → [../vmware-bootc/README-BASTION.md](../vmware-bootc/README-BASTION.md) — same steps, swap `vmware-bootc` → `vmware-minimal`.

### Boot order (what happens inside each VM)

1. OpenRC mounts the root filesystem **read-write** and loads VMware NIC drivers (`e1000` / `vmxnet3`)
2. `local` service runs `00-network-wait` — waits for `eth0`, starts DHCP, fixes DNS
3. `todo-db` or `todo-web` service starts — runs the preloaded Podman image
4. On **todo-web only**: iptables redirects port 80 → 8080

---

## Step 2 — Create your credentials file

Still on the bastion:

```bash
cp credentials.env.example credentials.env
vi credentials.env
```

(`nano credentials.env` works too if you prefer.)

### What is `credentials.env`?

It's a small file with **your secrets and sandbox-specific settings**. Ansible reads it when you run the playbook. Think of it as your "lab login details" file.

### Fill in your real values

Replace every `XXXXX` with your sandbox ID:

```yaml
govc_username: "sandbox-XXXXX@demo"
govc_password: "YourPasswordHere"
govc_datastore: "workload_share_XXXXX"

vm_network: "segment-sandbox-XXXXX"
vm_folder: "/SDDC-Datacenter/vm/Workloads/sandbox-XXXXX"
datastore_base: "Workload-Portability"
```

### What each setting means

| Setting | What it means |
|---------|---------------|
| `govc_username` / `govc_password` | Login for VMware vCenter (the tool that manages VMs) |
| `govc_datastore` | Where disk images get uploaded in VMware |
| `vm_network` | Which virtual network your VMs plug into |
| `vm_folder` | Which folder in vSphere your VMs appear in — **must** be your sandbox Workloads folder |
| `datastore_base` | Subfolder name on the datastore for your VMDK files |

### VM names (usually leave as-is)

```yaml
db01_vm_name: "todo-db"
web01_vm_name: "todo-web"
```

These are the names you'll see in vSphere and use in the browser URL.

> **Important:** `credentials.env` contains your real password. **Never commit it to git.**

### Offline container images (when quay.io denies pulls)

The playbook tries to `podman pull` on the **bastion** during build. If quay.io blocks pulls (a known lab issue), save the images elsewhere and copy them to the bastion first:

```bash
# On a machine that CAN pull from quay.io:
podman pull quay.io/rh-ee-sbajaj/todo-db:latest
podman pull quay.io/rh-ee-sbajaj/todo-web:latest
podman save -o todo-db.tar quay.io/rh-ee-sbajaj/todo-db:latest
podman save -o todo-web.tar quay.io/rh-ee-sbajaj/todo-web:latest
scp todo-db.tar todo-web.tar lab-user@bastion:~/minimal-build/
```

The playbook looks for these at `/root/minimal-build/todo-db.tar` and `todo-web.tar` when pulls fail.

---

## Step 3 — Run the playbook

Use `sudo` — the playbook needs root to mount disks, build images, and write to `/root/minimal-build/`:

```bash
git pull   # always pull latest fixes before building
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env   # optional: clean slate
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

### What happens (expect 15–30+ minutes)

Here's the order, in plain English:

1. **Installs build tools** on the bastion (if missing)
2. **Builds todo-db disk** — Alpine rootfs + preloaded `todo-db` container image in Podman storage
3. **Uploads todo-db disk** to VMware datastore
4. **Creates todo-db VM** in your sandbox folder and powers it on
5. **Waits for todo-db IP** via VMware Tools (pauses ~2 minutes on first boot)
6. **Builds todo-web disk** — Alpine rootfs + preloaded `todo-web` image with `DB_HOST` set to the IP from step 5
7. **Uploads todo-web disk** and **creates todo-web VM**
8. **Waits for todo-web IP**
9. **Configures bastion firewall** — forwards port 80 on the bastion → todo-web port 80

You'll see lots of Ansible output scroll by. That's normal. Wait until it says `PLAY RECAP` with no failed tasks.

### Where build files end up

When you use `sudo`, artifacts go here:

```
/root/minimal-build/
├── govc.env              # VMware connection settings (auto-generated)
├── todo-db/
│   └── output/disk.vmdk  # database disk image
└── todo-web/
    └── output/disk.vmdk  # web disk image
```

---

## Step 4 — Check it worked

### A) VMs visible in vSphere

In the VMware UI, under **Workloads → sandbox-XXXXX**, you should see:

- `todo-db` — powered on
- `todo-web` — powered on

### B) Get VM IP addresses from the bastion

```bash
sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-db

sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web
```

You should get private IPs like `192.168.x.x`. Write down the **todo-web** IP.

### C) Test the web app from the bastion (internal test)

```bash
WEB_IP=$(sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web)

curl -I http://$WEB_IP
```

You should see `HTTP/1.1 200` (or `301`/`302`) — not `Connection refused`.

Test the database port:

```bash
DB_IP=$(sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-db)

timeout 3 bash -c "echo >/dev/tcp/$DB_IP/5432" && echo "DB port open" || echo "DB port closed"
```

### D) Check the bastion firewall rule

```bash
sudo firewall-cmd --list-forward-ports
```

Should show something like:

```
port=80:proto=tcp:toport=80:toaddr=192.168.x.x
```

That means: "traffic hitting the bastion on port 80 gets forwarded to the todo-web VM."

---

## Step 5 — Open the app in your laptop browser

### The URL pattern

Your demo environment has **wildcard DNS** — a fancy way of saying any hostname under your cluster domain points at the bastion:

```
*.cluster-XXXXX.dyn.redhatworkshops.io  →  bastion public IP
```

Use your **web VM name** in the URL:

```
http://YOUR_WEB_VM_NAME.cluster-XXXXX.dyn.redhatworkshops.io
```

### Example

If your web VM is named `todo-web` and sandbox is `vn5tw`:

```
http://todo-web.cluster-vn5tw.dyn.redhatworkshops.io
```

Replace:
- `YOUR_WEB_VM_NAME` → value of `web01_vm_name` in `credentials.env` (default: `todo-web`)
- `XXXXX` → your sandbox ID (e.g. `vn5tw`)

### How traffic flows (don't skip this — it explains a common mistake)

```
Your laptop browser
  → http://todo-web.cluster-vn5tw.dyn.redhatworkshops.io
  → DNS sends you to the bastion's public IP, port 80
  → bastion firewalld forwards to todo-web private IP, port 80
  → Podman container running the todo web app
  → app talks to todo-db over the private network
```

> **Do NOT** put `192.168.x.x` in your laptop browser. That private IP only works **inside** the lab network (e.g. from the bastion). Your laptop is outside that network — use the `*.cluster-XXXXX.dyn.redhatworkshops.io` URL instead.

### Optional: SSH into the web VM

```bash
ssh demo@<todo-web-private-ip>
# password: demo
```

Useful commands on **todo-web**:

```sh
sudo podman ps -a
sudo podman logs todo-web
sudo rc-status
```

Useful commands on **todo-db** (vSphere console only — no SSH):

```sh
sudo podman ps -a
sudo podman logs todo-db
sudo rc-service todo-db status
```

---

## Optional — Run one stage at a time

You don't have to run everything in one go.

```bash
# Database VM only
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags db01

# Web VM only (todo-db must already exist and have an IP)
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags web01

# Bastion firewall only (e.g. todo-web IP changed)
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags bastion-firewall
```

### If todo-db already exists and you only want todo-web

Add the database IP to your credentials or command line:

```bash
# Option 1 — in credentials.env:
# db_host: "192.168.x.x"

# Option 2 — on the command line:
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env \
  -e db_host=192.168.x.x \
  --tags web01,bastion-firewall
```

**Why?** The web disk image needs to know the database IP **at build time** (unlike bootc, which configures it over SSH afterwards).

---

## Cleanup when you're done

Removes VMs, disk images, firewall rules, and local build files.

```bash
cd ~/workload-portability/ansible/vmware-minimal
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
```

### What gets removed

| Step | What |
|------|------|
| Bastion firewall | HTTP forward rule, port 80 allowance |
| VMware VMs | Powers off and destroys `todo-web`, then `todo-db` |
| Datastore | Uploaded VMDKs and the `Workload-Portability/` folder |
| Bastion disk | `/root/minimal-build/` |

### Cleanup one part at a time

```bash
# VMs only
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vms

# Datastore VMDKs only
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vmdks

# Bastion firewall only
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags bastion-firewall

# Local build files only
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags local
```

---

## If something goes wrong

### Recommended first step

Always pull the latest playbook fixes, then do a clean rebuild:

```bash
cd ~/workload-portability/ansible/vmware-minimal
git pull
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

If quay.io denies pulls during build, copy offline image tars first (see [Offline container images](#offline-container-images-when-quayio-denies-pulls)).

### "Permission denied" or Podman errors

Make sure you're using `sudo`:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

### `No package qemu-img available` or `no enabled repositories`

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

### Playbook hangs waiting for VM IP

`govc vm.ip` needs **open-vm-tools** running inside the guest. First boot can take **2+ minutes** before the IP appears.

1. Check the VM console in vSphere — did Alpine boot? Look for `[ ok ] Starting todo-db container`
2. Wait longer: `-e vm_first_boot_pause=180`
3. Or set static IPs in `credentials.env` to skip discovery:

```yaml
db01_static_ip: "192.168.x.x"
web01_static_ip: "192.168.x.x"
```

### `todo-db failed to start` on VM console

Common causes and fixes:

| Console message | Cause | Fix |
|-----------------|-------|-----|
| `eth0: No such device` / `ifup failed` | VMware NIC not ready at boot | `git pull` and rebuild (network-wait fix) |
| `Read-only file system` | Root disk not remounted rw | `git pull` and rebuild (OpenRC `root` service fix) |
| `podman pull failed` | quay.io denied or no internet on VM | `git pull` and rebuild (images preloaded at build time) |
| `container image missing from VMDK` | VMDK built without preloaded image | Rebuild with `build-minimal-vms.yml` |

On a running VM, try manually on the **todo-db console**:

```sh
mount -o remount,rw /
sudo rc-service todo-db restart
sudo podman ps -a
```

### quay.io denies pulls (build time)

VMs **must not** pull from quay.io at runtime. Images are preloaded into Podman storage during the bastion build.

If the bastion also cannot pull, use [offline image tars](#offline-container-images-when-quayio-denies-pulls).

### Web app loads but can't reach the database

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

### `ss: not found` on todo-web

Harmless. The startup script tries to list open ports with `ss`, which is not installed on minimal Alpine. The container still starts — ignore this message if `podman ps` shows `todo-web` as **Up**.

### `govc.env` not found

When you run with `sudo`, the file is at `/root/minimal-build/govc.env` (not your home directory):

```bash
sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web
```

### VMDK shows as "Locked" in vSphere

A previous upload may have left a stuck lock. Run cleanup, then re-run:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vmdks
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags db01
```

### VMs already exist from a previous run

Either destroy them first:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env --tags vms
```

Or delete them manually in vSphere, then re-run the build playbook.

### Browser URL doesn't load

Work through this list in order:

1. **Internal test first:** `curl -I http://<todo-web-ip>` from bastion — do you get `HTTP/1.1 200`?
2. **DB port open:** `timeout 3 bash -c "echo >/dev/tcp/<todo-db-ip>/5432"` — must succeed
3. **Firewall rule:** `sudo firewall-cmd --list-forward-ports` — does `toaddr` match the **current** todo-web IP?
4. **Re-apply firewall** if the VM IP changed (DHCP):

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags bastion-firewall
```

5. **Don't run nginx on the bastion** on port 80 — it fights with `firewalld` forwarding.

### Conflicts with bootc track

Both tracks use VM names `todo-db` and `todo-web`. If you switched tracks, clean up the old one first.

---

## Glossary (words you'll see)

| Term | Plain English |
|------|---------------|
| **Bastion** | The jump-box Linux VM in your lab — where you run the playbook |
| **VMDK** | Virtual hard disk file uploaded to VMware |
| **Alpine Linux** | A minimal Linux distro — very small, good for tiny VMs |
| **Podman** | Container runtime (like Docker) — runs the actual todo app |
| **govc** | Command-line tool for VMware — uploads disks, creates VMs |
| **Ansible playbook** | Automated script written as steps — `build-minimal-vms.yml` |
| **Role** | Reusable chunk of Ansible tasks — `alpine-vmdk`, `vmware-vm`, etc. |
| **firewalld** | Linux firewall on the bastion — used to forward port 80 to your web VM |
| **Wildcard DNS** | `*.cluster-XXXXX...` URLs all resolve to the bastion public IP |
| **Embedded image** | Container image saved into the VMDK at build time — VMs load it locally at boot |
| **Host networking** | Podman runs containers with `--network host` instead of port mapping |
| **streamOptimized** | VMDK format VMware prefers for uploads — single file, compact |

---

## Files you might care about

| File | What it is |
|------|------------|
| `build-minimal-vms.yml` | **Main playbook** — run this to build and deploy |
| `cleanup-minimal-vms.yml` | **Teardown playbook** — run when you're done |
| `credentials.env` | Your secrets (you create this — never commit it) |
| `credentials.env.example` | Safe template to copy from |
| `group_vars/all.yml` | Default settings (disk size, VM specs, image names) |
| `roles/alpine-vmdk/` | Builds the small Alpine disk |
| `roles/vmware-vm/` | Uploads disk and creates VM in VMware |
| `roles/bastion-firewall/` | Sets up browser access via bastion |

Build output (with `sudo`): `/root/minimal-build/`

---

## Quick reference (copy-paste)

```bash
# On bastion:
cd ~/workload-portability/ansible/vmware-minimal
git pull
cp credentials.env.example credentials.env   # first time only
vi credentials.env                           # fill in sandbox ID + password
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

Verify from bastion:

```bash
curl -I http://$(sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web)
```

Then open in your laptop browser:

```
http://todo-web.cluster-XXXXX.dyn.redhatworkshops.io
```

Cleanup when finished:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
```
