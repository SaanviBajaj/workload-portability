# Cleanup — Tear Down VMs and Demo Resources

Use this guide when you're finished with the demo and want to remove everything the build playbook created.

**Built and deployed the VMs?** → You probably came from [README.md](README.md)

---

## What gets removed

| Step | What |
|------|------|
| Bastion firewall | HTTP forward rule, port 80 allowance |
| VMware VMs | Powers off and destroys `todo-web`, then `todo-db` |
| Datastore | Uploaded VMDKs and the `Workload-Portability/` folder |
| Bastion disk | `~/bootc-build/` or `/root/bootc-build/` |

---

## Before you start

On the **bastion VM**:

```bash
cd ~/workload-portability/ansible/vmware-bootc
git pull
```

You need:

- The same `credentials.env` you used for the build playbook
- `govc.env` still present at `/root/bootc-build/govc.env` (if you ran build with `sudo`)

---

## Full cleanup (one command)

```bash
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env
```

This runs all cleanup steps in order:

1. Remove bastion `firewalld` forward to `todo-web`
2. Power off and destroy VMs
3. Delete VMDKs from the datastore
4. Remove `Workload-Portability/db01/`, `Workload-Portability/web01/`, and `Workload-Portability/`
5. Delete local build files under `bootc-build/`

---

## Cleanup one part at a time

```bash
# VMs only
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags vms

# Datastore VMDKs and Workload-Portability folder
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags vmdks

# Bastion firewall only
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags bastion-firewall

# Local build files only
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags local
```

---

## Optional settings

Add to `credentials.env` or pass with `-e`:

```yaml
cleanup_vms: true                  # destroy todo-db and todo-web (default: true)
cleanup_datastore_vmdks: true      # remove VMDK files (default: true)
cleanup_datastore_folder: true     # remove Workload-Portability folder (default: true)
cleanup_bastion_firewall: true     # remove firewall forward rule (default: true)
cleanup_local_build: true          # remove ~/bootc-build (default: true)
cleanup_podman_images: false        # also remove local bootc image tags (default: false)
cleanup_remove_masquerade: false    # remove masquerade — only if nothing else needs it
```

### Examples

Keep build files for a faster rebuild:

```bash
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env -e cleanup_local_build=false
```

Remove VMs but keep the datastore folder:

```bash
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags vms
```

---

## Verify cleanup

### VMs gone

```bash
sudo podman run --rm --env-file /root/bootc-build/govc.env \
  docker.io/vmware/govc:latest /govc ls -l "/SDDC-Datacenter/vm/Workloads/sandbox-XXXXX"
```

Replace `sandbox-XXXXX` with your sandbox folder. `todo-db` and `todo-web` should be gone.

### Datastore folder gone

```bash
sudo podman run --rm --env-file /root/bootc-build/govc.env \
  docker.io/vmware/govc:latest /govc datastore.ls
```

`Workload-Portability/` should no longer appear (or be empty).

### Firewall rule gone

```bash
sudo firewall-cmd --list-forward-ports
```

Port 80 forward to `todo-web` should be removed.

### Local build gone

```bash
sudo ls /root/bootc-build
# No such file or directory
```

---

## If something goes wrong

### `govc.env` not found

The cleanup playbook needs `govc.env` from the original build. If you already deleted `bootc-build/`, recreate it:

```bash
# Copy credentials and render govc.env manually, or re-run build playbook header tasks
```

Easiest fix: run cleanup **before** deleting `bootc-build/` manually.

### VM destroy fails

Power off manually in vSphere, then re-run:

```bash
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags vms
```

### Datastore folder won't delete

Delete remaining files in vSphere under **Workload-Portability**, then re-run:

```bash
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env --tags vmdks
```

---

## Re-deploy after cleanup

To build everything again from scratch:

```bash
sudo ansible-playbook build-bootc-vms.yml -e @credentials.env
```

See [README.md](README.md) for the full build guide.
