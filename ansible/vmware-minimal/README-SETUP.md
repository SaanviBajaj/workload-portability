# VMware Minimal — Setup (Before You Start)

Get the bastion ready and copy the playbook files before you run the build.

**Main guide:** [README.md](README.md)

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

## Next steps

Continue in the main guide:

1. [Step 2 — Create your credentials file](README.md#step-2--create-your-credentials-file)
2. [Step 3 — Run the playbook](README.md#step-3--run-the-playbook)
