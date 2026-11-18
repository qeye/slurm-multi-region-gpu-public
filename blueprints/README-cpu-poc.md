# CPU-only multi-region PoC

Drop-in CPU variant of `blueprints/cluster.yaml`: same single-cluster,
multi-region Slurm layout, but with `c3-standard-4` nodes and no GPU, RDMA,
Lustre or custom-image pieces.

| | GPU reference | CPU PoC |
|---|---|---|
| Compute | 11 Spot nodesets of a3-ultra/mega/high (H200/H100) | 4 nodesets of `c3-standard-4`, up to 2 nodes each |
| Regions | us-central1, us-south1, us-west1, us-east4, us-east5 | us-central1 (W1), us-east4 (W2), us-west1 (W3), us-east5 (W4) |
| Partition | `gpu` | `cpu` (region features: `uscentral1`, `useast4`, `uswest1`, `useast5`) |
| Image | Custom Packer build (`build-lustre-image.yaml`) | Public `slurm-gcp-6-12-hpc-rocky-linux-8`, no build step |
| /home | Filestore BASIC_SSD 2.5 TiB | NFS from the controller (Filestore block left commented out) |
| /lustre | Managed Lustre 18 TiB | removed |
| /gcs | Multi-region HNS bucket | same |
| Controller / login | n2-standard-16 / n2-standard-4 | n2-standard-4 / n2-standard-2 |
| Spot | always | off by default (`use_spot: true` to turn it on) |

## Files

- `blueprints/cluster-cpu.yaml` — the blueprint
- `blueprints/cluster-cpu-deployment.yaml` — per-deployment vars
- `tests/jobs/cpu_multiregion.sh` — smoke test, one job per region

## Deploy

```bash
export PROJECT_ID=$(gcloud config get-value project)

# Same bootstrap as the GPU cluster. Its NAT regions already cover all four
# PoC regions. The Lustre and GPU-quota steps don't affect this blueprint.
./scripts/setup-project.sh

# Check C3 quota in each region (needs 8 vCPU per region at nodes_per_region=2)
for r in us-central1 us-east4 us-west1 us-east5; do
  gcloud compute regions describe $r --format="table(quotas.filter(metric:C3_CPUS))"
done

gcluster deploy blueprints/cluster-cpu.yaml \
  -d blueprints/cluster-cpu-deployment.yaml \
  --vars project_id=$PROJECT_ID --auto-approve
```

## Test

```bash
LOGIN=$(gcloud compute instances list --filter="name~login" --format="value(name)" | head -1)
gcloud compute ssh "$LOGIN" --zone us-central1-a --tunnel-through-iap
# on the login node (copy the test script over first, or paste it):
bash cpu_multiregion.sh
squeue
cat /gcs/poc/*.txt   # each line shows the zone the job ran in
```

You should see one result from each of the four regions, and the unpinned job
in us-central1.

## Tear down

```bash
gcluster destroy slurm-cpu-poc --auto-approve
```

## If something fails

- **`Invalid value for field ... diskType`**: C3 can't use `pd-standard`.
  The blueprint sets `pd-balanced`. Keep it that way if you change machine types.
- **Nodes never reach IDLE in a non-central region**: check that the
  `VmDnsSetting=GlobalOnly` step in `setup-project.sh` ran, and that Cloud NAT
  exists in that region.
- **Boot fails with Secure Boot errors**: set `enable_secure_boot: false` in the
  affected module's `shielded_instance_config`.
- **Zone has no C3 capacity**: change `zone:`/`zones:` on that nodeset. To
  list zones that offer C3 in a region:
  `gcloud compute machine-types list --filter="name=c3-standard-4 AND zone~^us-east5"`.
