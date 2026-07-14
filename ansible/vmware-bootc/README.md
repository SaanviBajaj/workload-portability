# VMware Bootc VM Build — Step-by-Step Guide

This playbook builds and deploys two VMs for the todo app demo:

| VM name (default) | What it does |
|-------------------|--------------|
| `todo-db` | Database (PostgreSQL) |
| `todo-web` | Web app |

**Run everything on your bastion VM** (the VM from the demo environment).

**Need to copy these files onto the bastion first?** → See [README-BASTION.md](README-BASTION.md)

---

## Before you start

On the **bastion VM**, check these are installed:

```bash
ansible-playbook --version
podman --version
```

You also need:

- Your **vCenter password** (from the demo environment)
- Your **sandbox ID** (e.g. `sandbox-vn5tw` — yours will differ)
- VMs must land in **`Workloads/sandbox-XXXXX`** in vSphere to be visible in your sandbox

---

## What the playbook builds

Each VM boots from a **CentOS Stream 9 bootc** disk image built on the bastion.

| Output | Size (approx.) |
|--------|----------------|
| `db01/output/vmdk/disk.vmdk` | **~1.7 GB** (thin provisioned) |
| `web01/output/vmdk/disk.vmdk` | **~1.7 GB** (thin provisioned) |

VM sizing defaults: **2 vCPU**, **4 GB RAM**, `pvscsi` disk controller.

---

## Step 1 — Get the files onto the bastion

```bash
cd ~/workload-portability
git pull
cd ansible/vmware-bootc
```

First time? See **[README-BASTION.md](README-BASTION.md)**.

---

## Step 2 — Create your credentials file

```bash
cp credentials.env.example credentials.env
vi credentials.env
```

Replace every `XXXXX` with your sandbox values:

```yaml
govc_username: "sandbox-XXXXX@demo"
govc_password: "YourPasswordHere"
govc_datastore: "workload_share_XXXXX"

vm_network: "segment-sandbox-XXXXX"
vm_folder: "/SDDC-Datacenter/vm/Workloads/sandbox-XXXXX"
datastore_base: "Workload-Portability"    # or your datastore folder name
```

Default VM names (change only if you want different names):

```yaml
db01_vm_name: "todo-db"
web01_vm_name: "todo-web"
```

> **Important:** `credentials.env` has your real password. Do not commit it.

---

## Step 3 — Run the playbook

Use `sudo` so Podman can build images and write to `/root/bootc-build/`:

```bash
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env
```

### What happens (10–20+ minutes)

1. Builds **todo-db** bootc image (~1.7 GB VMDK) and uploads to vSphere
2. Creates `todo-db` VM in your sandbox folder
3. Discovers DB IP (via VMware Tools) and builds **todo-web** image (~1.7 GB VMDK)
4. Creates `todo-web` VM
5. SSHes into `todo-web` — sets `DB_HOST` / `DB_PORT` for the app
6. Configures **bastion `firewalld`** — forwards port **80 → todo-web:80** for external browser access

---

## Step 4 — Check it worked

### VMs in vSphere

Under **Workloads → sandbox-XXXXX** you should see:

- `todo-db`
- `todo-web`

### From the bastion (internal test)

```bash
curl http://$(sudo podman run --rm --env-file /root/bootc-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web)
```

You should see Todo App HTML.

### Firewall rule on bastion

```bash
sudo firewall-cmd --list-forward-ports
```

Should show something like:

```
port=80:proto=tcp:toport=80:toaddr=192.168.x.x
```

---

## Step 5 — Access the app in a browser

Wildcard DNS for your sandbox points at the **bastion**:

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

### How it works

```
Browser
  → todo-web.cluster-vn5tw.dyn.redhatworkshops.io
  → bastion public IP :80
  → bastion firewalld forward
  → todo-web VM :80
  → Todo App
```

> **Do not** use the private IP (`192.168.x.x`) in your laptop browser — that only works inside the lab network.

### SSH into the web VM (optional)

```bash
ssh demo@<todo-web-private-ip>
# password: demo
```

---

## Optional: run one stage at a time

```bash
# Database only
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env --tags db01

# Web only (after db01)
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env --tags web01

# DB connection config on todo-web only
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env --tags configure

# Bastion firewall forward only (e.g. after VM IP changed)
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env --tags bastion-firewall
```

If `todo-db` already exists:

```bash
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env \
  -e db_host=<your-todo-db-ip> \
  --tags web01,configure,bastion-firewall
```

---

## If something goes wrong

### Podman permission errors

```bash
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env
```

### Playbook hangs waiting for VM IP

```bash
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env -e vm_ip_wait=10m
```

Or set the DB IP manually:

```bash
# in credentials.env:
db_host: "192.168.x.x"
```

### `govc.env` not found (ran with sudo)

The env file lives at `/root/bootc-build/govc.env` when using sudo:

```bash
sudo podman run --rm --env-file /root/bootc-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web
```

### VMDK shows as "Locked" in vSphere

Delete the stuck VMDK, then re-run `--tags db01` or `--tags web01`.

### VMs already exist

Delete VMs (and VMDKs) in vSphere, then re-run the full playbook.

### Browser URL doesn't load

1. Confirm bastion firewall rule: `sudo firewall-cmd --list-forward-ports`
2. Confirm app works internally: `curl http://<todo-web-ip>` from bastion
3. Re-run firewall step if VM IP changed: `--tags bastion-firewall`
4. Do **not** run a separate nginx proxy on port 80 — it conflicts with `firewalld` forwarding

### Web app can't reach the database

```bash
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env \
  -e db_host=<todo-db-ip> \
  --tags configure
```

---

## Files you might care about

| File | What it is |
|------|------------|
| `build-bootc-vms.yml` | Main playbook |
| `credentials.env` | Your secrets (create from example) |
| `credentials.env.example` | Safe template |
| `group_vars/all.yml` | Defaults (placeholders) |

Build output: `~/bootc-build/` (or `/root/bootc-build/` if using `sudo`).

---

## Quick reference

```bash
cd ~/workload-portability/ansible/vmware-bootc
git pull
cp credentials.env.example credentials.env
vi credentials.env
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env
```

Then open in a browser:

```
http://YOUR_WEB_VM_NAME.cluster-XXXXX.dyn.redhatworkshops.io
```
