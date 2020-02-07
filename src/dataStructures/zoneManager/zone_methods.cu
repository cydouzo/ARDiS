#include "dataStructures/helper/apply_operation.h"
#include "hediHelper/cuda/cuda_device_converter.h"
#include "matrixOperations/basic_operations.hpp"
#include "rectangle_zone.hpp"
#include <dataStructures/array.hpp>

__global__ void IsInsideArrayK(D_Array &mesh_x, D_Array &mesh_y,
                               RectangleZone &zone, D_Array &is_inside,
                               T value) {
    int i = threadIdx.x + blockIdx.x * blockDim.x;
    if (i >= is_inside.n)
        return;
    is_inside.vals[i] =
        (zone.IsInside(mesh_x.vals[i], mesh_y.vals[i])) ? value : 0;
}
D_Array IsInsideArray(D_Array &mesh_x, D_Array &mesh_y, RectangleZone &zone,
                      T value = 1) {
    assert(mesh_x.n == mesh_y.n);
    RectangleZone *d_zone;
    cudaMalloc(&d_zone, sizeof(RectangleZone));
    cudaMemcpy(d_zone, &zone, sizeof(RectangleZone), cudaMemcpyHostToDevice);

    D_Array is_inside(mesh_x.n);
    auto tb = Make1DThreadBlock(mesh_x.n);
    IsInsideArrayK<<<tb.block, tb.thread>>>(*mesh_x._device, *mesh_y._device,
                                            *d_zone, *is_inside._device, value);
    return is_inside;
    cudaFree(d_zone);
}

void FillZone(D_Array &u, D_Array &mesh_x, D_Array &mesh_y, RectangleZone &zone,
              T value) {
    // HDData v
    auto setToVal = [value] __device__(T & a) { a = value; };
    auto is_inside = IsInsideArray(mesh_x, mesh_y, zone);
    ApplyFunctionConditional(u, is_inside, setToVal);
}

void FillOutsideZone(D_Array &u, D_Array &mesh_x, D_Array &mesh_y,
                     RectangleZone &zone, T value) {
    auto setToVal = [value] __device__(T & a) { a = value; };
    D_Array is_outside(u.n);
    is_outside.Fill(1);
    auto is_inside = IsInsideArray(mesh_x, mesh_y, zone);
    HDData<T> m1(-1);
    VectorSum(is_outside, is_inside, is_outside, m1(true));
    ApplyFunctionConditional(u, is_inside, setToVal);
}

T GetMinZone(D_Array &u, D_Array &mesh_x, D_Array &mesh_y,
             RectangleZone &zone) {
    auto min = [] __device__(T & a, T & b) { return (a < b) ? a : b; };
    D_Array u_copy(u);
    auto is_inside = IsInsideArray(mesh_x, mesh_y, zone);
    ReductionFunctionConditional(u_copy, is_inside, min);
    T result = -1;
    cudaMemcpy(&result, u_copy.vals, sizeof(T), cudaMemcpyDeviceToHost);
    return result;
};

T GetMaxZone(D_Array &u, D_Array &mesh_x, D_Array &mesh_y,
             RectangleZone &zone) {
    auto max = [] __device__(T & a, T & b) { return (a > b) ? a : b; };
    D_Array u_copy(u);
    auto is_inside = IsInsideArray(mesh_x, mesh_y, zone);
    ReductionFunctionConditional(u_copy, is_inside, max);
    T result = -1;
    cudaMemcpy(&result, u_copy.vals, sizeof(T), cudaMemcpyDeviceToHost);
    return result;
};

T GetMeanZone(D_Array &u, D_Array &mesh_x, D_Array &mesh_y,
              RectangleZone &zone) {
    D_Array ones(u.n);
    ones.Fill(1);
    auto is_inside = IsInsideArray(mesh_x, mesh_y, zone, (T)(1.0));
    HDData<T> n(0);
    Dot(ones, is_inside, n(true));
    n.SetHost();
    HDData<T> result(0);
    Dot(u, is_inside, result(true));
    result.SetHost();
    return result() / n();
};