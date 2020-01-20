#include "cuda_runtime.h"
#include <assert.h>
#include <stdio.h>

#include "cudaHelper/cuda_error_check.h"
#include "dot_sparse.hpp"
#include "sparseDataStruct/double_data.hpp"
#include "sparseDataStruct/matrix_element.hpp"

#include "cudaHelper/cuda_thread_manager.h"

__global__ void DotK(MatrixSparse &d_mat, VectorDense &x, VectorDense &y) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i >= d_mat.i_size)
        return;
    MatrixElement it(d_mat.rowPtr[i], &d_mat);
    y.vals[i] = 0;
    do {
        y.vals[i] += it.val[0] * x.vals[it.j];
        it.Next();
    } while (it.i == i && it.HasNext());
}

void Dot(MatrixSparse &d_mat, VectorDense &x, VectorDense &result,
         bool synchronize) {
    assert(d_mat.isDevice && x.isDevice && result.isDevice);
    dim3Pair threadblock = Make1DThreadBlock(d_mat.i_size);
    DotK<<<threadblock.block, threadblock.thread>>>(*d_mat._device, *x._device,
                                                    *result._device);

    if (synchronize)
        cudaDeviceSynchronize();
    else
        return;
}

__device__ T *buffer;
int bufferCurrentSize = 0;
__global__ void AllocateBuffer(int size) {
    if (buffer)
        delete[] buffer;
    buffer = new T[size];
}

__global__ void DotK(VectorDense &x, VectorDense &y) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i >= x.n)
        return;
    T safVal = x.vals[i];
    x.vals[i] = y.vals[i] * safVal;
    __syncthreads();
    for (int exp = 0; (1 << exp) < blockDim.x; exp++) {
        if (threadIdx.x % (2 << exp) == 0 &&
            threadIdx.x + (1 << exp) < blockDim.x) {
            x.vals[i] += x.vals[i + (1 << exp)];
        }
        __syncthreads();
    }
    if (threadIdx.x == 0)
        buffer[blockIdx.x] = x.vals[i];
    x.vals[i] = safVal;
    return;
}

__global__ void SumBlocks(T &result, int nValues) {
    result = 0;
    for (int b = 0; b < nValues; b++)
        result += buffer[b];
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i >= nValues)
        return;
    for (int exp = 0; (1 << exp) < blockDim.x; exp++) {
        if (threadIdx.x % (2 << exp) == 0 &&
            threadIdx.x + (1 << exp) < blockDim.x) {
            buffer[i] += buffer[i + (1 << exp)];
        }
        __syncthreads();
    }
    if (i == 0)
        result = buffer[i];
}

void Dot(VectorDense &x, VectorDense &y, double &result, bool synchronize) {
    assert(x.isDevice && y.isDevice);
    assert(x.n == y.n);
    dim3Pair threadblock = Make1DThreadBlock(x.n);
    if (bufferCurrentSize < threadblock.block.x) {
        AllocateBuffer<<<1, 1>>>(threadblock.block.x);
        bufferCurrentSize = threadblock.block.x;
    }
    DotK<<<threadblock.block, threadblock.thread>>>(*x._device, *y._device);
    cudaDeviceSynchronize();
    do {
        int nValues = threadblock.block.x;
        threadblock.block.x =
            int((threadblock.block.x - 1) / threadblock.thread.x) + 1;
        SumBlocks<<<threadblock.block.x, threadblock.thread.x>>>(result,
                                                                 nValues);
        cudaDeviceSynchronize();
    } while (threadblock.block.x > 1);
    if (synchronize)
        cudaDeviceSynchronize();
    else
        return;
}

__global__ void VectorSumK(VectorDense &a, VectorDense &b, T &alpha,
                           VectorDense &c) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i >= a.n)
        return;
    c.vals[i] = a.vals[i] + b.vals[i] * alpha;
};

void VectorSum(VectorDense &a, VectorDense &b, T &alpha, VectorDense &c,
               bool synchronize) {
    assert(a.isDevice && b.isDevice);
    assert(a.n == b.n);
    dim3Pair threadblock = Make1DThreadBlock(a.n);
    VectorSumK<<<threadblock.block, threadblock.thread>>>(
        *a._device, *b._device, alpha, *c._device);
    if (synchronize)
        cudaDeviceSynchronize();
}

void VectorSum(VectorDense &a, VectorDense &b, VectorDense &c,
               bool synchronize) {
    HDData<T> alpha(1.0);
    VectorSum(a, b, alpha(true), c, synchronize);
}

__device__ inline bool IsSup(MatrixElement &it_a, MatrixElement &it_b) {
    return (it_a.i == it_b.i && it_a.j > it_b.j) || it_a.i > it_b.i;
};

__device__ inline bool IsEqu(MatrixElement &it_a, MatrixElement &it_b) {
    return (it_a.i == it_b.i && it_a.j == it_b.j);
};

__device__ inline bool IsSupEqu(MatrixElement &it_a, MatrixElement &it_b) {
    return (it_a.i == it_b.i && it_a.j >= it_b.j) || it_a.i > it_b.i;
};

__global__ void SumNNZK(MatrixSparse &a, MatrixSparse &b, int &nnz) {
    MatrixElement it_a(&a);
    MatrixElement it_b(&b);
    nnz = 0;
    while (it_a.HasNext() || it_b.HasNext()) {
        if (IsEqu(it_a, it_b)) {
            it_a.Next();
            it_b.Next();
            nnz++;
        } else if (IsSup(it_a, it_b)) {
            it_b.Next();
            nnz++;
        } else if (IsSup(it_b, it_a)) {
            it_a.Next();
            nnz++;
        } else {
            printf("Error! Nobody was iterated in SumNNZK function.\n");
            return;
        }
    }
}

__global__ void AllocateSumK(MatrixSparse &a, MatrixSparse &b, T &alpha,
                             MatrixSparse &c) {
    // int i = threadIdx.x + blockIdx.x * blockDim.x;
    // if (i >= a.i_size)
    //     return;
    MatrixElement it_a(&a);
    MatrixElement it_b(&b);
    c.AddElement(0, 0, 0.0);
    MatrixElement it_c(&c);

    while (it_a.HasNext() || it_b.HasNext()) {
        if (IsSupEqu(it_a, it_b)) {
            if (IsEqu(it_b, it_c))
                it_c.val[0] += it_b.val[0];
            else {
                c.AddElement(it_b.i, it_b.j, it_b.val[0]);
                it_c.Next();
            }
            it_b.Next();
        }
        if (IsSupEqu(it_b, it_a)) {
            if (IsEqu(it_a, it_c))
                it_c.val[0] += it_a.val[0];
            else {
                c.AddElement(it_a.i, it_a.j, it_a.val[0]);
                it_c.Next();
            }
            it_a.Next();
        }
    }
}

void MatrixSum(MatrixSparse &a, MatrixSparse &b, T &alpha, MatrixSparse *c,
               bool synchronize) {
    // This method is only impleted in the specific case of CSR matrices
    assert(a.type == CSR && b.type == CSR);
    assert(a.i_size == b.i_size && a.j_size == b.j_size);
    HDData<int> nnz(0);
    SumNNZK<<<1, 1>>>(*a._device, *b._device, nnz(true));
    cudaDeviceSynchronize();
    nnz.SetHost();
    c = new MatrixSparse(a.i_size, a.j_size, nnz(), COO, true);
    // dim3Pair threadblock = Make1DThreadBlock(a.i_size);
    AllocateSumK<<<1, 1>>>(*a._device, *b._device, alpha, *c->_device);
    cudaDeviceSynchronize();
    assert(c->IsConvertibleTo(CSR));
    c->ConvertMatrixToCSR();
    return;
}

void MatrixSum(MatrixSparse &a, MatrixSparse &b, MatrixSparse *c,
               bool synchronize) {
    HDData<T> alpha(1.0);
    MatrixSum(a, b, alpha(true), c, synchronize);
}