# VMware Minimal VM Build — Step-by-Step Guide

This playbook builds and deploys two **small** VMs for the todo app demo:

| VM name (default) | What it does |
|-------------------|--------------|
| `todo-db` | Database (PostgreSQL) |
| `todo-web` | Web app (the page you open in a browser) |

**Run everything on your bastion VM** — the Linux VM in your demo environment that can talk to VMware.

This is the **minimal** track. It makes **much smaller disk images** than the bootc track (~700 MB vs ~1.7 GB per VM).

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
| Disk size | ~1.7 GB per VM | **~500–800 MB per VM** (under 1 GB) |
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
| `todo-db` | `todo-db/output/disk.vmdk` | **~500–800 MB** |
| `todo-web` | `todo-web/output/disk.vmdk` | **~500–800 MB** |

The playbook builds these on the bastion using:

- **Alpine Linux** — a very small Linux distro (not a full CentOS install)
- **Podman** — runs the actual todo app containers inside the VM
- **qemu-img** — creates and converts the virtual disk

### What's inside each VM?

**todo-db VM:**
- Tiny Alpine Linux (just enough to boot and run Podman)
- On startup, automatically runs the `todo-db` container (PostgreSQL on port 5432)
- No SSH login (you manage it through VMware/vCenter)

**todo-web VM:**
- Tiny Alpine Linux + SSH (user `demo` / password `demo`)
- On startup, automatically runs the `todo-web` container (web app on port 80)
- Knows where the database is (`DB_HOST` is baked into the image at build time)

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

---

## Step 3 — Run the playbook

Use `sudo` — the playbook needs root to mount disks, build images, and write to `/root/minimal-build/`:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

### What happens (expect 10–20+ minutes)

Here's the order, in plain English:

1. **Installs build tools** on the bastion (if missing)
2. **Builds todo-db disk** — creates a 700 MB Alpine image with the database container baked in
3. **Uploads todo-db disk** to VMware datastore
4. **Creates todo-db VM** in your sandbox folder and powers it on
5. **Waits for todo-db IP** — VMware Tools reports the VM's private IP (e.g. `192.168.x.x`)
6. **Builds todo-web disk** — same Alpine process, but includes the database IP so the web app knows where to connect
7. **Uploads todo-web disk** and **creates todo-web VM**
8. **Waits for todo-web IP**
9. **Configures bastion firewall** — forwards port 80 on the bastion → todo-web port 80 (so your laptop can open the app)

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
curl http://$(sudo podman run --rm --env-file /root/minimal-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web)
```

You should see HTML containing "Todo" or similar — not an error page.

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

Useful for troubleshooting. The database VM has no SSH.

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

The playbook waits for VMware Tools to report an IP. If a VM booted but has no IP:

1. Check the VM console in vSphere — is Alpine booting? Any errors?
2. Wait longer:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env -e vm_ip_wait=10m
```

3. Or set the IP manually in `credentials.env`:

```yaml
db_host: "192.168.x.x"
```

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

1. **Internal test first:** `curl http://<todo-web-ip>` from bastion — does that work?
2. **Firewall rule:** `sudo firewall-cmd --list-forward-ports` — is there a rule pointing at todo-web?
3. **Re-apply firewall** if the VM IP changed:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env --tags bastion-firewall
```

4. **Don't run nginx on the bastion** on port 80 — it fights with `firewalld` forwarding.

### Web app loads but can't reach the database

The web image was probably built **before** the database had an IP. Rebuild todo-web with the correct `db_host`:

```bash
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env \
  -e db_host=<todo-db-ip> \
  --tags web01
```

You may also need to destroy the old todo-web VM first if the disk changed.

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
cp credentials.env.example credentials.env
vi credentials.env          # fill in sandbox ID + password
sudo ansible-playbook build-minimal-vms.yml -e @credentials.env
```

Then open in your laptop browser:

```
http://todo-web.cluster-XXXXX.dyn.redhatworkshops.io
```

Cleanup when finished:

```bash
sudo ansible-playbook cleanup-minimal-vms.yml -e @credentials.env
```
