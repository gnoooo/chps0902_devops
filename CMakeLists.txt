cmake_minimum_required(VERSION 3.16)
project(bcast C)

find_package(MPI REQUIRED)

add_executable(bcast src/bcast.c)
target_link_libraries(bcast PRIVATE MPI::MPI_C)

enable_testing()
add_test(NAME bcast_np4
         COMMAND ${MPIEXEC_EXECUTABLE} ${MPIEXEC_NUMPROC_FLAG} 4
                 ${MPIEXEC_PREFLAGS} $<TARGET_FILE:bcast>)
