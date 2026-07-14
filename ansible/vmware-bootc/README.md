# VMware Bootc VM Build — Step-by-Step Guide

This playbook builds and deploys two VMs for the todo app demo:

| VM name | What it does |
|---------|--------------|
| `todo-db` | Database (PostgreSQL) |
| `todo-web` | Web app |

**Run everything on your bastion VM** (the VM from the demo environment). You do not run this from your laptop unless that laptop *is* the bastion.

**Need to copy these files onto the bastion first?** → See [README-BASTION.md](README-BASTION.md)

---

## Before you start

Make sure you are logged into the **bastion VM**, then check these are installed:

```bash
ansible-playbook --version
podman --version
```

You also need:

- Your **vCenter password** (from the demo environment)
- Your **sandbox ID** (looks like `sandbox-6qtqn` — yours will be different)

---

## Step 1 — Get the files onto the bastion

If the playbook isn't on the bastion yet, follow **[README-BASTION.md](README-BASTION.md)** first.

Then go to the playbook folder:

```bash
cd ~/workload-portability/ansible/vmware-bootc
```

If you used a different path when copying, adjust accordingly. You should see `build-bootc-vms.yml` and `credentials.env.example`.

---

## Step 2 — Create your credentials file

Copy the example file:

```bash
cp credentials.env.example credentials.env
```

Open it for editing:

```bash
vi credentials.env
```

### What to change

Replace every `XXXXX` with **your** sandbox details. At minimum, change these lines:

```yaml
govc_username: "sandbox-XXXXX@demo"      # → your sandbox username
govc_password: "YourPasswordHere"        # → your real vCenter password
govc_datastore: "workload_share_XXXXX"   # → your datastore name

vm_network: "segment-sandbox-XXXXX"      # → your network segment
vm_folder: "/SDDC-Datacenter/vm/Workloads/sandbox-XXXXX"  # → your VM folder
```

**Leave these as-is** unless you want different VM names:

```yaml
db01_vm_name: "todo-db"
web01_vm_name: "todo-web"
```

Save and exit (`:wq` in vi).

> **Important:** `credentials.env` contains your real password. It is already in `.gitignore` — do not commit or share it.

---

## Step 3 — Run the playbook

This one command does everything (build images, upload disks, create VMs, configure the web app):

```bash
ansible-playbook build-bootc-vms.yml -e @credentials.env
```

### What happens (takes a while)

1. Builds the **database** VM disk image
2. Uploads it to VMware and creates `todo-db`
3. Waits for the database VM to get an IP address
4. Builds the **web** VM disk image
5. Uploads it to VMware and creates `todo-web`
6. SSHes into `todo-web` and tells the web app where the database is
7. Opens bastion `firewalld` port 80 forward to `todo-web` (external access)

Go get a coffee — image builds can take 10–20+ minutes.

---

## Step 4 — Check it worked

### In VMware (vSphere)

Look for two new VMs in your sandbox folder:

- `todo-db`
- `todo-web`

Both should be **powered on**.

### From the bastion

Get the web VM IP:

```bash
podman run --rm --env-file ~/bootc-build/govc.env \
  docker.io/vmware/govc:latest /govc vm.ip todo-web
```

Open that IP in a browser (port 80). You should see the todo app.

### SSH into the web VM (optional)

```bash
ssh demo@<todo-web-ip>
# password: demo
```

---

## If something goes wrong

### "Permission denied" during podman build

Your user needs sudo. The playbook uses sudo by default. Make sure you can run:

```bash
sudo podman ps
```

### Playbook hangs waiting for VM IP

VMware Tools may be slow to start. Wait a few minutes, or re-run with a longer timeout:

```bash
ansible-playbook build-bootc-vms.yml -e @credentials.env -e vm_ip_wait=10m
```

### Web app loads but can't reach the database

Re-run just the configure step (replace the IP with your `todo-db` IP):

```bash
ansible-playbook build-bootc-vms.yml -e @credentials.env \
  -e db_host=192.168.108.25 \
  --tags configure
```

### VMDK shows as "Locked" in vSphere

Delete the stuck VMDK in vSphere, then re-run:

```bash
ansible-playbook build-bootc-vms.yml -e @credentials.env --tags db01
# or
ansible-playbook build-bootc-vms.yml -e @credentials.env --tags web01
```

### VMs already exist from a previous run

The playbook skips VM creation if `todo-db` / `todo-web` already exist. To start fresh, delete the VMs (and their VMDKs) in vSphere first, then re-run Step 3.

---

## Optional: run one VM at a time

You usually don't need this, but if you want to go step by step:

```bash
# Database only
ansible-playbook build-bootc-vms.yml -e @credentials.env --tags db01

# Web only (run after db01 is done)
ansible-playbook build-bootc-vms.yml -e @credentials.env --tags web01

# Configure web app only (DB connection)
ansible-playbook build-bootc-vms.yml -e @credentials.env --tags configure

# Bastion firewall only (port 80 forward to todo-web)
ansible-playbook build-bootc-vms.yml -e @credentials.env --tags bastion-firewall
```

If `todo-db` already exists and you only need to build/configure the web tier:

```bash
ansible-playbook build-bootc-vms.yml -e @credentials.env \
  -e db_host=<your-todo-db-ip> \
  --tags web01,configure
```

---

## Files you might care about

| File | What it is |
|------|------------|
| `build-bootc-vms.yml` | The main playbook — you run this |
| `credentials.env` | **Your** secrets and sandbox settings (you create this) |
| `credentials.env.example` | Template — safe to commit, has no real password |
| `group_vars/all.yml` | Default settings (placeholders only) |

Build output lands in `~/bootc-build/` on the bastion. You don't need to touch it manually.

---

## Quick reference — the whole process

```bash
cd ~/workload-portability/ansible/vmware-bootc
cp credentials.env.example credentials.env
vi credentials.env                    # fill in your sandbox ID + password
ansible-playbook build-bootc-vms.yml -e @credentials.env
```

That's it.
