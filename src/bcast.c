#include <mpi.h>
#include <stdio.h>

#define N 8

int main(int argc, char **argv)
{
    int rank, size, i, errors = 0;
    int data[N];

    MPI_Init(&argc, &argv);
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);

    /* seul le rang 0 connait les valeurs, les autres doivent les recevoir */
    for (i = 0; i < N; i++)
        data[i] = (rank == 0) ? i * 10 : -1;

    MPI_Bcast(data, N, MPI_INT, 0, MPI_COMM_WORLD);

    for (i = 0; i < N; i++) {
        if (data[i] != i * 10) {
            printf("rang %d valeur %d attendue %d\n", rank, data[i], i * 10);
            errors++;
        }
    }

    printf("rang %d recoit %d\n", rank, data[0]);

    if (rank == 0)
        printf("MPI_Bcast OK sur %d rangs\n", size);

    MPI_Finalize();
    return errors != 0;
}
