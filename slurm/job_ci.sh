#!/bin/bash
#SBATCH --job-name=ci-bcast
#SBATCH --output=ci-%j.out
#SBATCH --partition=debug
#SBATCH --nodes=2
#SBATCH --ntasks=2
#SBATCH --ntasks-per-node=1
#SBATCH --mem=0
#SBATCH --time=00:10:00

set -e
cd "$SLURM_SUBMIT_DIR"

# un job batch ne passe pas par /etc/profile, on initialise Spack et Lmod a la main
for f in 01-spack z00_lmod z00_spack_lmod; do . "/etc/profile.d/$f.sh"; done
module load openmpi

srun ./build/bcast
echo "SUCCESS: test MPI passe sur $(scontrol show hostnames "$SLURM_JOB_NODELIST" | tr '\n' ' ')"
