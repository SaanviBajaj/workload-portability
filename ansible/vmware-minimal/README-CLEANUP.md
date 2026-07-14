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

---

## Switching from the bootc track

Both tracks use VM names `todo-db` and `todo-web`. Clean up the bootc VMs first:

```bash
cd ~/workload-portability/ansible/vmware-bootc
sudo ansible-playbook cleanup-bootc-vms.yml -e @credentials.env
```

See also: [Troubleshooting — Conflicts with bootc track](README-TROUBLESHOOTING.md#conflicts-with-bootc-track)
