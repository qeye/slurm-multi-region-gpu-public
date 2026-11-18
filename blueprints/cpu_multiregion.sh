#!/bin/bash
# Smoke test for blueprints/cluster-cpu.yaml.
#
# Submits one job pinned to each region's nodeset (via the region Feature),
# plus one unpinned job that should land on the lowest-Weight nodeset
# (us-central1). Each job records where it ran into /gcs and /home.
#
# Run from the login node:
#   bash tests/jobs/cpu_multiregion.sh
#   squeue            # wait until all jobs finish (first boot ~3-5 min/region)
#   cat /gcs/poc/*.txt

set -euo pipefail

mkdir -p /gcs/poc "$HOME/poc"

submit() {
  local name="$1"; shift
  sbatch --parsable --partition=cpu --nodes=1 --ntasks=1 --time=00:10:00 \
    --job-name="poc-${name}" --output="$HOME/poc/%x-%j.out" "$@" --wrap '
      ZONE=$(curl -s -H "Metadata-Flavor: Google" \
        http://metadata.google.internal/computeMetadata/v1/instance/zone | awk -F/ "{print \$NF}")
      MT=$(curl -s -H "Metadata-Flavor: Google" \
        http://metadata.google.internal/computeMetadata/v1/instance/machine-type | awk -F/ "{print \$NF}")
      LINE="job=$SLURM_JOB_ID name=$SLURM_JOB_NAME host=$(hostname) zone=$ZONE type=$MT cpus=$(nproc) date=$(date -u +%FT%TZ)"
      echo "$LINE"
      echo "$LINE" > /gcs/poc/${SLURM_JOB_NAME}-${SLURM_JOB_ID}.txt
      ls -ld /home /gcs >/dev/null && echo "shared mounts OK"
    '
}

for region in uscentral1 useast4 uswest1 useast5; do
  echo "submitted $(submit "$region" --constraint="$region") -> $region"
done
echo "submitted $(submit unpinned) -> unpinned (expect us-central1, Weight 1)"

echo
echo "Watch with: squeue; sinfo -N -o '%N %f %T'"
echo "Results:    cat /gcs/poc/*.txt"
