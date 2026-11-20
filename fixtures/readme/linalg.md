# linalg

Dense linear algebra for Nabi on core's `Array`: cache-blocked and
parallel products, LU, Cholesky and LDL^T, Householder QR (with column
pivoting), SVD, symmetric and general eigenproblems, the real Schur form,
least squares, pseudo-inverse, determinants, norms, condition numbers and
the matrix exponential. f64 first; f32, `Complex<f64>` and `Complex<f32>`
wherever the algorithm is the same. Pure Nabi, so it runs on every target,
wasm included.

## Add it

```sh
nabi add linalg
```

Needs Nabi 0.1 or later.

## Usage

```nabi
use core::array::{Matrix, Vector};
use linalg::mat!;

let a = mat![4, 1, 0; 1, 3, 1; 0, 1, 2];     // or let a: Matrix<f64> = [[4, 1, 0], ...]
let b: Vector<f64> = [1, 2, 3];

let x = try linalg::solve(a, b);              // LU with partial pivoting
let r = a @ x .- b |> linalg::norm;           // residual, about 1e-16
let c = try linalg::cholesky(a);              // a is positive definite
let e = try linalg::eigh(a);                  // eigenvalues rising, orthonormal vectors
let s = try linalg::svd(a);                   // s.u(), s.s(), s.vt()
println(f"{x:?} {e.values():?} cond {try linalg::cond(a)}");

// Least squares: fit y = c0 + c1 t.
let t: Matrix<f64> = [[1, 0], [1, 1], [1, 2], [1, 3]];
let y: Vector<f64> = [1.0, 2.9, 5.1, 7.0];
let coef = try linalg::lstsq(t, y);
```

Factorizations are types: build one, then `solve` as many right-hand
sides as you like (a vector, or a matrix of columns), or read `det`,
`inv` and the factors.

```nabi
use core::array::{Matrix, Vector};

let a: Matrix<f64> = [[4, 1, 0], [1, 3, 1], [0, 1, 2]];
let b: Vector<f64> = [1, 2, 3];
let f = try linalg::lu(a);
let x1 = try f.solve(b);
let xs = try f.solve(linalg::eye::<f64>(3));  // the inverse, column by column
println(f"{f.det()}");
```

Errors are one `LinalgError` (`Singular`, `NotSquare`, `ShapeMismatch`,
`NotPositiveDefinite`, `NoConvergence`, `NotFinite`); each message says
what to call instead.

## Array-like input

`linalg::AsVector<T>` is the one-dimensional input the science packages
share: a `Vector<T>`, a `List<T>`, a fixed array, and for `f64` also
lists and vectors of `f32` or integers and an integer range. Vectors and
lists are shared, the rest converted once. `stats`, `signal`,
`interpolate`, `ode`, `optimize`, `sparse` and `autodiff` take it, so
data comes in the same way everywhere:

```nabi
use linalg::AsVector;
use core::array::Vector;

fn total<X: AsVector<f64>>(x: X) -> f64 {
    let v: Vector<f64> = x.as_vector();
    v.sum()
}

let xs: List<i64> = [1, 2, 3];
assert(total(xs) == 6.0 && total(1..4) == 6.0 && total([0.5f32, 1.5f32]) == 2.0);
```

## Operators

With the `ops` feature (on by default) matrix code reads like the math:

| Operator         | Meaning                                       | Named form                 |
|------------------|-----------------------------------------------|----------------------------|
| `a @ b`, `a ⊡ b` | matrix product (matrix or vector either side) | `linalg::matmul`, `matvec` |
| `a ⊗ b`          | Kronecker product; outer product of vectors   | `linalg::kron`, `outer`    |
| `a \ b`, `a ⧵ b` | solve `a x = b` (least squares if not square) | `linalg::solve`, `lstsq`   |
| `a†`             | adjoint (conjugate transpose)                 | `linalg::adjoint`          |

`@` (as in NumPy) and `\` (as in MATLAB and Julia) are the ASCII
spellings; `⊡` and `⧵` are the same operators. `@`, `⊡` and `⊗` bind
like `*`, `\` and `⧵` like `/`, `†` like a postfix `?`: `a† @ a .+ 1.0`
is `((a†) @ a) .+ 1.0`. Operators cannot throw, so `@` panics on a shape
mismatch (as `.+` does) and `\` returns a `Result`:

```nabi
use linalg::ops::*;
use core::array::{Matrix, Vector};

let a: Matrix<f64> = [[2, 1], [1, 3]];
let b: Vector<f64> = [1, 2];
let g = a† @ a;
let x = try (a \ b).get();
let k = linalg::eye::<f64>(2) ⊗ g;
```

Build without the feature (`default_features: false`) if the tokens
clash with another package's.

## What is in it

| Area            | Items                                                                 |
|-----------------|-----------------------------------------------------------------------|
| Products        | `matmul`, `matvec`, `vecmat`, `dot`, `vdot`, `outer`, `kron`, `matrix_power` |
| Building        | `eye`, `diag`, `diagonal`, `trace`, `adjoint`, `mat!`                 |
| Factorizations  | `lu`, `cholesky`, `ldlt`, `qr`, `qr_pivoted`, `svd`, `svd_full`, `eigh`, `eig`, `schur` |
| Solvers         | `solve`, `lstsq`, `solve_triangular`, `inv`, `pinv`                   |
| Quantities      | `det`, `slogdet`, `rank`, `cond`, `null_space`, `svdvals`, `eigvalsh` |
| Norms           | `norm`, `vector_norm`, `matrix_norm` (`Norm::One`, `Two`, `Inf`, `Fro`) |
| Functions       | `expm`                                                                |

Methods: LU with partial pivoting (blocked), Cholesky, LDL^T without
pivoting, Householder QR (LAPACK conventions, optional column pivoting),
SVD after a QR for tall input (one-sided Jacobi on a pivoted R up to 16
columns, Golub-Kahan bidiagonalization and implicit-shift QR above),
symmetric eigen by Householder tridiagonalization and implicit QL, general
eigen by Hessenberg reduction and Francis double-shift QR, least squares by
pivoted QR and a complete orthogonal decomposition for rank-deficient
problems, `expm` by scaling and squaring with Pade approximants (Higham
2005). Each function's docs give its accuracy and cost.

## Speed

`matmul` of f64, GFLOP/s (2mnk flops per call), `nabi bench matmul` at
-O2 on an Apple M-series machine (12 cores) under load from other jobs,
best of three interleaved runs; "1 core" is the same kernel with the
parallel split turned off.

| Shape (m x k x n)  | All cores | 1 core |
|--------------------|----------:|-------:|
| 64 x 64 x 64       |        17 |     17 |
| 256 x 256 x 256    |        57 |     25 |
| 512 x 512 x 512    |        96 |     27 |
| 1024 x 1024 x 1024 |       122 |     28 |
| 2048 x 2048 x 2048 |       139 |     29 |
| 64 x 4000 x 64     |        30 |     20 |
| 4000 x 64 x 64     |        37 |     20 |
| 512 x 512 x 512, f32 |     146 |     51 |

The kernel packs B into 128 x 256 panels and updates 4-row tiles of C
four `k` at a time, so each load of B feeds four rows; it runs at the
rate of separate multiplies and adds (about 8 flops a cycle on one
core). An optimized BLAS (OpenBLAS, Accelerate) uses fused multiply-add
and reaches roughly 2-3x this per core, and Accelerate more again on
the matrix unit. LU, `solve` and `expm` call the same kernel for their
blocked updates.

## Docs

https://packages.nabi-lang.org/packages/linalg/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
