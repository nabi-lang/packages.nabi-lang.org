# autodiff

Automatic differentiation for Nabi on core's `Array`: forward mode with
dual numbers (one direction, or `N` directions per evaluation), hyper-dual
numbers for exact Hessians, Taylor jets for derivatives of any order, and
reverse mode on a tape for gradients of many inputs in one backward sweep.
Write a function once over `Smooth` and run it in every mode. Every
derivative is exact to rounding: no step sizes. f64. Pure Nabi, so it runs
on every target, wasm included.

## Add it

```sh
nabi add autodiff
```

Needs Nabi 0.1 or later. Depends on `linalg`.

## Usage

```nabi
use autodiff::{Dual, HyperDual, Jet, Smooth, Var};
use core::array::{Array, Vector};

fn rosen<T: Smooth>(x: Vector<T>) -> T {
    let a = x[1].clone() - x[0].clone() * x[0].clone();
    let b = T::of(1.0) - x[0].clone();
    a.clone() * a * 100.0 + b.clone() * b
}

let x: Vector<f64> = [-1.2, 1.0];
let g = autodiff::grad(rosen::<Var>, x);          // reverse mode: one sweep
assert(g == autodiff::grad(rosen::<Dual>, x));    // forward mode: n evaluations
let h = autodiff::hessian(rosen::<HyperDual>, x); // exact second derivatives
assert(h[0, 1] == 480.0);

let d = autodiff::derivative(|x: Dual| -> Dual { x.sin() * x }, 1.0);
let taylor = autodiff::derivatives(|x: Jet| -> Jet { x.exp() * x }, 0.0, 4);   // f, f', .., f''''
assert(taylor.to_list() == [0.0, 1.0, 2.0, 3.0, 4.0]);

let f = |x: Vector<Var>| -> Vector<Var> { Array::from([x[0] * x[1], x[0].sin()]) };
let j = autodiff::jacobian(f, [2.0, 3.0]);        // by rows: one sweep per output
let w = autodiff::vjp(f, [2.0, 3.0], [1.0, 0.0]); // w^T J in one sweep
```

`grad`, `value_grad`, `jacobian` and `value_jacobian` take the mode from
the number type the function is written over, and any `linalg::AsVector`
point (a `Vector`, a list, an integer range):

| Function over    | Gradient of f: R^n -> R          | Jacobian of R^n -> R^m        |
|------------------|----------------------------------|-------------------------------|
| `Dual`           | n evaluations                    | n evaluations (by columns)    |
| `Duals<N>`       | ceil(n / N) evaluations          | ceil(n / N) evaluations       |
| `Var`            | 1 evaluation + 1 backward sweep  | 1 evaluation + m sweeps (rows)|

`hessian` (over `HyperDual`) takes n (n + 1) / 2 evaluations; `jvp` (over
`Dual`) and `vjp` (over `Var`) one. A `Tape` can also be used by hand:
`t.var(x)`, compute, `y.backward().wrt(x)`. A `Var` clone is the same
variable; every `Var` of one computation must come from one tape.

## Notation

With the `ops` feature (on by default):

| Notation      | Meaning                                                    | Named form                  |
|---------------|------------------------------------------------------------|-----------------------------|
| `3.0 + 1.0ε`  | the dual number 3 + ε (a number suffix)                    | `Dual::var(3.0)`            |
| `∂(f)`        | f' as a function (f over `Dual`, `Var`, `HyperDual`, `Jet`) | `derivative(f, x)`         |
| `∂(f, n)`     | the n-th derivative as a function (f over `Jet`; `HyperDual` up to 2) | `derivatives(f, x, n)` |
| `∇(f)`        | the gradient (or Jacobian) of f as a function              | `grad(f, x)`, `jacobian(f, x)` |
| `∇(a)`        | the gradient of samples `a` on a unit grid, as samples      | interpolate's `gradient`    |

`∂` and `∇` return the derivative in the form of what they are given,
never a value at a point: a function for a function, a spline for a
spline, samples for samples. The value is `∂(f)(x)` / `∇(f)(x)`. They
dispatch through the public traits `Derive` and `Gradient`, so other
packages extend the same two names for their own types (interpolate's
splines and polynomials) and re-export them: `use interpolate::ops::*`
and `use optimize::ops::*` together bring one `∂` and one `∇`.

```nabi
use autodiff::{Dual, Jet, Var};
use autodiff::ops::{∂, ∇};
use core::array::Vector;

let fp = ∂(|x: Dual| -> Dual { x.sin() });
assert(fp(0.0) == 1.0);
let f3 = ∂(|x: Jet| -> Jet { x.powi(4) }, 3);
assert(f3(1.0) == 24.0);
let g = ∇(|x: Vector<Var>| -> Var { x[0] * x[1] });
assert(g([2.0, 5.0]).to_list() == [5.0, 2.0]);
let y: Vector<f64> = [0, 1, 4, 9];
assert(∇(y).to_list() == [1.0, 2.0, 4.0, 5.0]);
```

## Speed

Gradient of Rosenbrock's function, Apple M-series core, `nabi bench`
(-O2), per gradient:

| n     | `Dual`  | `Duals<8>` | `Var`   | one f64 evaluation |
|-------|---------|------------|---------|--------------------|
| 10    | 1.1 us  | 2.3 us     | 1.2 us  |                    |
| 100   | 106 us  | 141 us     | 10.6 us | 0.63 us            |
| 1000  | 11.0 ms | 14.5 ms    | 140 us  |                    |
| 10000 |         |            | 1.3 ms  |                    |

Reverse mode costs about 15-20 evaluations whatever n is; forward mode
grows with n. `Duals<N>` does fewer evaluations but its lane loops are
not yet vectorized, so it does not beat `Dual` today; use `Var` for many
inputs.

## Docs

https://packages.nabi-lang.org/packages/autodiff/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
