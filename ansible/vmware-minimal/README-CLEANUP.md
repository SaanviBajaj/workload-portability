# VMware Minimal — Cleanup

Tear down VMs, datastore disks, firewall rules, and local build files when you're done.

**Main guide:** [README.md](README.md)

---

## Full cleanup

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

### Manual datastore cleanup (when UI or playbook leaves orphans)

VMware cannot delete a **folder** while a **VMDK file** is still inside it. Destroy VMs first, then remove files, then folders.

```bash
GOVC="sudo podman run --rm --env-file /root/minimal-build/govc.env docker.io/vmware/govc:latest /govc"

# See what is left
$GOVC datastore.ls Workload-Portability/
$GOVC datastore.ls Workload-Portability/todo-db/ 2>/dev/null || true

# Delete VMDK files first (both subfolder and orphan root copies)
$GOVC datastore.rm Workload-Portability/todo-db/todo-db-disk1.vmdk
$GOVC datastore.rm Workload-Portability/todo-db-disk1.vmdk
$GOVC datastore.rm Workload-Portability/todo-web/todo-web-disk1.vmdk
$GOVC datastore.rm Workload-Portability/todo-web-disk1.vmdk

# Then delete folders
$GOVC datastore.rm Workload-Portability/todo-db
$GOVC datastore.rm Workload-Portability/todo-web
$GOVC datastore.rm Workload-Portability
```

If `datastore.rm` says the file is locked, power off and destroy the VM in vSphere (or cancel MTV migration plans), wait 60s, retry.

---

## Switching from the bootc track

Both tracks use VM names `todo-db` and `todo-web`. Clean up the bootc VMs first:

```bash
cd ~/workload-portability/ansible/vmware-bootc
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env
```

See also: [Troubleshooting — Conflicts with bootc track](README-TROUBLESHOOTING.md#conflicts-with-bootc-track)
