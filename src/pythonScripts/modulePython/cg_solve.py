import numpy as np
import random
from scipy.sparse import *
import scipy.sparse.linalg as spLnal


def CGNaiveSolve(M, b, x, epsilon=1e-1):
    r = b-M.dot(x)
    p = r.copy()
    diff = abs(r.dot(p))
    diff0 = diff
    assert(diff > 0)
    nIter = 0

    while diff >= epsilon*epsilon*diff0 and nIter < 10000:
        q = M.dot(p)
        alpha = diff / q.dot(p)

        x += alpha * p
        r -= alpha * q

        diffnew = r.dot(r)
        beta = diffnew / diff
        diff = diffnew

        p = r + beta * p
        assert(diff > 0)
        nIter += 1

    if nIter == 10000:
        print("Error didnt converge")
    # print("niter: ", nIter, " : ", diff)
    return x