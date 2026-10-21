#!/bin/bash
#SBATCH --job-name=ci-bcast
#SBATCH --output=ci-%j.out
#SBATCH --partition=debug
#SBATCH --nodes=2
#SBATCH --ntasks=4
#SBATCH --ntasks-per-node=2
#SBATCH --time=00:10:00

set -e
cd "$SLURM_SUBMIT_DIR"

# l'image fournit Lmod mais un job n'est pas une session de login
source /etc/profile.d/z00_lmod.sh
module load openmpi

srun ./build/bcast
echo "SUCCESS: test MPI passe sur $(scontrol show hostnames "$SLURM_JOB_NODELIST" | tr '\n' ' ')"
