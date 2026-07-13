# How to Copy These Files onto the Bastion VM

The playbook must run **on the bastion VM**, not on your laptop.

This guide shows how to get the `ansible/vmware-bootc/` files from your Mac/laptop onto the bastion.

Once the files are there, go back to [README.md](README.md) and follow the main steps.

---

## What you need first

- **Bastion IP or hostname** — from your demo environment (e.g. `192.168.1.50` or `bastion.sandbox.example.com`)
- **Bastion username** — usually your demo user (e.g. `demo` or your Red Hat username)
- **SSH access** — you can log in with `ssh user@bastion-ip`
- **Podman** — to build images and talk to vCenter (often pre-installed, e.g. `5.6.0`)
- **Ansible** — `ansible-playbook` is **not** always pre-installed; install with `sudo dnf install -y ansible-core` (see [Install Podman and Ansible](#2-install-podman-and-ansible) below)

Replace these in the commands below:

| Placeholder | Example |
|-------------|---------|
| `BASTION_USER` | `demo` |
| `BASTION_HOST` | `192.168.1.50` |
| `LOCAL_REPO` | `~/Desktop/workload-portability` |

---

## Option A — Git clone on the bastion (best if the repo is on GitHub/GitLab)

Use this if your code is pushed to a git remote.

### On your laptop

Push your latest changes:

```bash
cd ~/Desktop/workload-portability
git add .
git commit -m "Add vmware-bootc playbook"
git push
```

### On the bastion

SSH in, then clone:

```bash
ssh BASTION_USER@BASTION_HOST

git clone https://github.com/SaanviBajaj/workload-portability.git
cd workload-portability/ansible/vmware-bootc
```

If the repo is private, use SSH clone or a personal access token.

To update later (after you push more changes from your laptop):

```bash
cd ~/workload-portability
git pull
```

---

## Option B — Copy with `scp` (simple, no git needed)

Use this for a one-off copy from your laptop to the bastion.

### On your laptop

Copy the whole project folder:

```bash
scp -r ~/Desktop/workload-portability BASTION_USER@BASTION_HOST:~/
```

Or copy **only** the playbook folder (smaller, faster):

```bash
scp -r ~/Desktop/workload-portability/ansible/vmware-bootc \
  BASTION_USER@BASTION_HOST:~/workload-portability/ansible/
```

### On the bastion

```bash
ssh BASTION_USER@BASTION_HOST
cd ~/workload-portability/ansible/vmware-bootc
ls
```

You should see `build-bootc-vms.yml`, `credentials.env.example`, `README.md`, etc.

---

## Option C — Copy with `rsync` (good for updates)

Use this when you already copied once and want to sync changes without re-copying everything.

### On your laptop

```bash
rsync -avz --progress \
  ~/Desktop/workload-portability/ansible/vmware-bootc/ \
  BASTION_USER@BASTION_HOST:~/workload-portability/ansible/vmware-bootc/
```

The trailing `/` matters — it syncs the **contents** of the folder.

Run the same command again anytime you edit files on your laptop.

---

## Option D — Zip and copy (if `scp -r` is slow or fails)

### On your laptop

```bash
cd ~/Desktop/workload-portability
tar czf vmware-bootc.tar.gz ansible/vmware-bootc
scp vmware-bootc.tar.gz BASTION_USER@BASTION_HOST:~/
```

### On the bastion

```bash
ssh BASTION_USER@BASTION_HOST
mkdir -p ~/workload-portability/ansible
tar xzf vmware-bootc.tar.gz -C ~/workload-portability/
cd ~/workload-portability/ansible/vmware-bootc
```

---

## After the files are on the bastion

### 1. Confirm you're in the right place

```bash
pwd
# should end in: .../ansible/vmware-bootc

ls build-bootc-vms.yml credentials.env.example README.md
```

### 2. Install Podman and Ansible

The playbook needs **both** tools on the bastion:

| Tool | What it does in this playbook |
|------|-------------------------------|
| `podman` | Builds bootc disk images and runs `govc` against vCenter |
| `ansible-playbook` | Runs `build-bootc-vms.yml` |

#### Check what you already have

```bash
podman --version
ansible-playbook --version
which podman
which ansible-playbook
```

Example of a ready bastion:

```text
podman version 5.6.0
ansible-playbook [core 2.16.x]
```

If `podman --version` works (e.g. `5.6.0`) but `ansible-playbook` is missing, you only need to install Ansible — see below.

#### Install Podman (if missing)

Demo bastions usually ship with Podman already. If `podman: command not found`:

```bash
sudo dnf install -y podman
```

Verify:

```bash
podman --version
sudo podman ps    # the playbook uses sudo for builds
```

#### Install Ansible / `ansible-playbook` (if missing)

On RHEL and Fedora, the `ansible-playbook` command comes from the **`ansible-core`** package:

```bash
sudo dnf install -y ansible-core
```

Verify:

```bash
ansible-playbook --version
```

You should see output like `ansible-playbook [core 2.x.x]`.

**No `sudo`?** Install into your user account with pip instead:

```bash
python3 -m pip install --user ansible-core
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
ansible-playbook --version
```

**`dnf` can't find `ansible-core`?** Enable the standard repos first (RHEL demo VMs usually have these already):

```bash
sudo subscription-manager repos --enable=rhel-*-for-*-appstream-rpms 2>/dev/null || true
sudo dnf install -y ansible-core
```

On Fedora, `ansible-core` is in the default repos — `sudo dnf install -y ansible-core` is enough.

### 3. Create your credentials file on the bastion

```bash
cp credentials.env.example credentials.env
vi credentials.env
```

Fill in your sandbox ID and vCenter password. See [README.md](README.md) Step 2 for details.

### 4. Run the playbook

```bash
ansible-playbook build-bootc-vms.yml -e @credentials.env
```

---

## Which option should I use?

| Situation | Use |
|-----------|-----|
| Repo is on GitHub and you'll update it often | **Option A** — git clone |
| Quick one-time copy, no git remote | **Option B** — scp |
| Already copied once, made local edits | **Option C** — rsync |
| Large folder or flaky network | **Option D** — tar + scp |

---

## Common problems

### `ansible-playbook: command not found`

Install the Ansible CLI on the bastion:

```bash
sudo dnf install -y ansible-core
ansible-playbook --version
```

If you used the pip method, make sure `~/.local/bin` is on your `PATH` (see [Install Podman and Ansible](#2-install-podman-and-ansible)).

### `Permission denied (publickey)`

Your SSH key isn't set up. Try password login if the demo allows it, or add your SSH key:

```bash
ssh-copy-id BASTION_USER@BASTION_HOST
```

### `scp: No such file or directory`

Check the path on your laptop exists:

```bash
ls ~/Desktop/workload-portability/ansible/vmware-bootc
```

Create the target directory on the bastion first:

```bash
ssh BASTION_USER@BASTION_HOST "mkdir -p ~/workload-portability/ansible"
```

### Files copied but playbook fails with "file not found"

You probably aren't in the playbook directory:

```bash
cd ~/workload-portability/ansible/vmware-bootc
```

### I edited files on my laptop — how do I update the bastion?

- **Git:** push from laptop, `git pull` on bastion
- **rsync:** re-run the rsync command from Option C
- **scp:** re-run the scp command from Option B

**Do not overwrite `credentials.env` on the bastion** if you already filled in your password. The rsync command above only updates playbook files in that folder — if you copied `credentials.env` manually, keep a backup or exclude it:

```bash
rsync -avz --progress \
  --exclude 'credentials.env' \
  ~/Desktop/workload-portability/ansible/vmware-bootc/ \
  BASTION_USER@BASTION_HOST:~/workload-portability/ansible/vmware-bootc/
```

---

## Next step

Files on the bastion? Credentials filled in?

→ Continue with [README.md](README.md)
