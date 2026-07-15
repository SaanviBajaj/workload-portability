# VMware Minimal VM Build — Step-by-Step Guide

This playbook builds and deploys two **small** VMs for the todo app demo:

| VM name (default) | What it does |
|-------------------|--------------|
| `todo-db` | Database (PostgreSQL) |
| `todo-web` | Web app (the page you open in a browser) |

**Run everything on your bastion VM** — the Linux VM in your demo environment that can talk to VMware.

This is the **minimal** track. It makes **smaller disk images** than the bootc track (~768 MB vs ~1.7 GB per VM).

**Important:** Container images are **preloaded into Podman storage at build time** on the bastion (no `.tar` left on disk). The VMs do **not** pull from quay.io at boot (quay.io often denies pulls in lab environments).

### Related guides

| Guide | When to use it |
|-------|----------------|
| [README-SETUP.md](README-SETUP.md) | **Before you start** — bastion prerequisites and **getting files onto the bastion** |
| [README-CLEANUP.md](README-CLEANUP.md) | **Tear down** VMs, VMDKs, firewall rules, and build files |
| [README-TROUBLESHOOTING.md](README-TROUBLESHOOTING.md) | **If something goes wrong** — common errors and fixes |

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
| Disk size | ~1.7 GB per VM | **~768 MB per VM** (preloaded container images, migration-ready) |
| Good when | You want a "real" RHEL-like VM | You want small disks for demos/migration |

Both tracks create the **same VM names** (`todo-db`, `todo-web`). **Do not run both at the same time** — pick one track.

If you already deployed the bootc VMs, see [README-CLEANUP.md](README-CLEANUP.md).

---

## What the playbook actually builds

### The disk image (VMDK)

Each VM boots from a **VMDK file** — think of it as a virtual hard drive you upload to VMware.

| VM | Build output on bastion | Size (approx.) |
|----|-------------------------|----------------|
| `todo-db` | `todo-db/output/disk.vmdk` | **~768 MB** provisioned |
| `todo-web` | `todo-web/output/disk.vmdk` | **~768 MB** provisioned |

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

## Step 2 — Create your credentials file

Still on the bastion. If you haven't copied the repo yet, start with [README-SETUP.md](README-SETUP.md).

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

See [README-CLEANUP.md](README-CLEANUP.md) for cleanup options.

### What happens (expect 15–30+ minutes)

Here's the order, in plain English:

1. **Installs build tools** on the bastion (if missing)
2. **Builds todo-db disk** — Alpine rootfs + preloaded `todo-db` container image in Podman storage
3. **Uploads todo-db disk** to VMware datastore
4. **Creates todo-db VM** in your sandbox folder and powers it on
5. **Waits for todo-db IP** via VMware Tools (`govc vm.ip`)
6. **Builds todo-web disk** — Alpine rootfs + preloaded `todo-web` image with `DB_HOST` set to the IP from step 5
7. **Uploads todo-web disk** and **creates todo-web VM**
8. **Waits for todo-web IP**
9. **Configures bastion firewall** — forwards port 80 on the bastion → todo-web port 80

You'll see lots of Ansible output scroll by. That's normal. Wait until it says `PLAY RECAP` with no failed tasks.

If something fails, see [README-TROUBLESHOOTING.md](README-TROUBLESHOOTING.md).

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
| **Preloaded image** | Container image loaded into Podman storage at build time — VMs run it locally at boot |
| **Host networking** | Podman runs containers with `--network host` instead of port mapping |
| **streamOptimized** | Compact single-file VMDK (legacy upload path) |
| **streamOptimized** | VMware import-friendly VMDK format required by `govc import.vmdk` |

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
| `README-SETUP.md` | Bastion prerequisites and getting files onto the bastion |
| `README-CLEANUP.md` | Teardown guide |
| `README-TROUBLESHOOTING.md` | Common errors and fixes |

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

Cleanup when finished — see [README-CLEANUP.md](README-CLEANUP.md).
