# optimize

Numerical optimization for Nabi on core's `Array`: roots and minima of
scalar functions, unconstrained minimization (Nelder-Mead, Powell,
conjugate gradients, BFGS, L-BFGS, Newton-CG, trust regions), box
constraints (L-BFGS-B, projected gradient), nonlinear constraints
(augmented Lagrangian), linear and convex quadratic programs (simplex,
interior point), nonlinear least squares and curve fitting
(Levenberg-Marquardt, trust-region reflective, robust losses), systems of
equations (Newton, Broyden, hybrid Powell) and global search (differential
evolution, basin hopping, simulated annealing). Derivatives come from you,
from automatic differentiation (autodiff's forward-mode `Dual` or
reverse-mode `Var`), from the complex step, or from finite differences. Pure Nabi on f64, so it runs on
every target, wasm included.

## Add it

```sh
nabi add optimize
```

Needs Nabi 0.1 or later. Depends on `linalg` and `autodiff`.

## Usage

```nabi
use optimize::{Bounds, Dual, Options};
use core::array::Vector;

// Write the objective over dual numbers: the gradient comes exact, by AD.
let rosen = |x: Vector<Dual>| -> Dual { 100.0 * (x[1] - x[0] ** 2) ** 2 + (1.0 - x[0]) ** 2 };

let m = try optimize::bfgs(rosen, [-1.2, 1.0]);
println(f"{m}");                                   // BFGS: converged: f = 3.8e-19 ... at x = [1.0, 1.0] ...

let b = try Bounds::new([-2.0, -2.0], [0.5, 2.0]);
let mb = try optimize::lbfgsb(rosen, [-1.2, 1.0], b);   // x = [0.5, 0.25]
assert(mb.x ∈ b);

// A plain closure works too: central differences give the gradient.
let s = try optimize::lbfgs(|x: Vector<f64>| -> f64 { (x[0] - 3.0) ** 2 + x[1] ** 2 }, [0.0, 0.0], Options { gtol: 1e-10 });

// Scalar roots and minima.
let r = try optimize::brentq(|x: f64| -> f64 { x.cos() - x }, 0.0, 1.0);
let t = try optimize::toms748(|x: f64| -> f64 { x ** 3 - 2.0 * x - 5.0 }, 2.0, 3.0);
let q = try optimize::minimize_scalar(|x: f64| -> f64 { (x - 1.5) ** 2 });
```

Every solver takes an objective as anything `IntoObjective`: a closure
over `f64`, `Dual`, `Var` (one backward sweep per gradient, the choice for
many variables) or `Complex<f64>`, or an `Objective` built with the
gradient, Hessian or Hessian-vector product you know
(`Objective::new(f).with_grad(g).with_hessp(hv)`); a closure may capture
data (a dataset, a matrix). Results carry the point, the value, the gradient,
the `Status` (why it stopped), iteration and evaluation counts and a
message; `Options` holds the tolerances, limits, line search, memory and a
callback that can stop a run.

Curve fitting with standard errors, here NIST's Misra1a with its certified
values:

```nabi
use optimize::Dual;
use core::array::Vector;

let x: Vector<f64> = [77.6, 114.9, 141.1, 190.8, 239.9, 289.0, 332.8, 378.4, 434.8, 477.3, 536.8, 593.1, 689.1, 760.0];
let y: Vector<f64> = [10.07, 14.73, 17.94, 23.93, 29.61, 35.18, 40.02, 44.82, 50.76, 55.05, 61.01, 66.40, 75.47, 81.78];
let model = |x: f64, b: Vector<Dual>| -> Dual { b[0] * (1.0 - (b[1] * -x).exp()) };
let fit = try optimize::curve_fit(model, x, y, [500.0, 1e-4]);
println(f"{fit.params:?} +- {fit.stderr:?}");     // [238.942129, 5.5015643e-4] +- [2.70700752, 7.2668688e-6]
```

Linear and quadratic programs are built row by row:

```nabi
use optimize::{Lp, Qp};

// max 3x + 2y with x + y <= 4, x + 3y <= 6, x <= 3.
let lp = Lp::new([-3.0, -2.0]).le([[1, 1], [1, 3], [1, 0]], [4.0, 6.0, 3.0]);
let r = try optimize::linprog(lp);                // f = -11 at [3, 1]

let qp = Qp::new([[2, 0], [0, 2]], [-2.0, -5.0]).le([[1, 2]], [3.0]);
let s = try optimize::quadprog(qp);               // x = [0.4, 1.3]
```

Errors are one `OptimizeError` (`NoSignChange`, `BadBracket`, `BadBounds`,
`ShapeMismatch`, `NotFinite`, `BadOption`, `Empty`, `Linalg`) for bad
input; each message says what to write instead. A run that does not
converge is not an error: its `status` says why.

## Notation

Dual numbers have the arithmetic operators (with an `f64` on either side),
`**` with an `i32`, `f64` or `Dual` exponent, prefix `√`, comparisons by
value and the elementary functions as methods. With the `ops` feature (on
by default) there is more:

| Notation          | Meaning                                         | Named form                   |
|-------------------|-------------------------------------------------|------------------------------|
| `3.0 + 1.0ε`      | the dual number 3 + ε (a number suffix)         | `Dual::var(3.0)`             |
| `c ⩽ b`           | the constraint `c(x) <= b` (level of `<=`)      | `Constraint::le(c, b)`       |
| `c ⩾ b`           | the constraint `c(x) >= b`                      | `Constraint::ge(c, b)`       |
| `c ≐ b`           | the constraint `c(x) = b` (level of `==`)       | `Constraint::eq(c, b)`       |
| `∇(f)`            | the gradient of `f` as a function, by AD        | `optimize::grad(f, x)`       |
| `∂(f)`            | `f'` as a function, for `f` over `Dual`         | `optimize::derivative(f, x)` |
| `x ∈ b`           | `x` inside the box `b` (core's `∈`, always on)  | `b.holds(x)`                 |

```nabi
use optimize::Dual;
use optimize::ops::∇;
use core::array::Vector;

let x = 2.0 + 1.0ε;
assert((x ** 3 + √x).du == 12.0 + 0.5 / 2.0f64.sqrt());

let budget = |x: Vector<f64>| -> f64 { x[0] + x[1] };
let area = |x: Vector<f64>| -> f64 { -(x[0] * x[1]) };
let m = try optimize::minimize(area, [0.1, 0.2], constraints: [budget ⩽ 1.0]);   // x = [0.5, 0.5]

let g = ∇(|x: Vector<Dual>| -> Dual { x[0] * x[1] });
assert(g([2.0, 3.0])[0] == 3.0);

// The pipe puts the objective first: f |> solver(x0).
let r = try optimize::problems::rosenbrock() |> optimize::lbfgs([-1.2, 1.0]);
```

`≤`, `≥` and `≡` cannot be registered (the lexer reads them as the fixed
`<=`, `>=` and `==`), hence the slanted `⩽` and `⩾`. `ε`, `∇` and `∂` are
autodiff's, re-exported: `∂` and `∇` return a derivative in the form of
what they are given (here a function; `∂(f)(x)` is the value), so this
module imports together with interpolate's `ops`. `∇` and `∂` are letters
to the lexer, so they are function names, not prefix operators.
Build without the feature (`default_features: false`) if the tokens clash
with another package's.

## What is in it

| Area                  | Items                                                                                   |
|-----------------------|-----------------------------------------------------------------------------------------|
| Scalar roots          | `bisect`, `brentq`, `ridder`, `toms748`, `newton`, `newton_ad`, `halley`, `secant`, `bracket_root` |
| Scalar minima         | `bracket`, `golden`, `brent`, `bounded`, `minimize_scalar`                              |
| Unconstrained         | `minimize`, `nelder_mead`, `powell`, `cg`, `bfgs`, `lbfgs`, `newton_cg`, `trust_dogleg`, `trust_ncg`, `line_search` |
| Bounds, constraints   | `Bounds`, `lbfgsb`, `projected_gradient`, `Constraint`, `auglag`                        |
| LP and QP             | `Lp`, `Qp`, `linprog` (`LpMethod::Simplex`, `InteriorPoint`), `quadprog`                |
| Least squares         | `least_squares` (`LsqMethod::Lm`, `Trf`), `curve_fit`, `Loss`, `Residuals`, `Model`     |
| Systems               | `root`, `hybr`, `root_newton`, `broyden` (`Broyden::Good`, `Bad`)                       |
| Global                | `differential_evolution`, `basin_hopping`, `simulated_annealing`                        |
| Derivatives           | `Dual`, `Smooth`, `grad`, `value_grad`, `jacobian`, `derivative`, `approx_grad`, `approx_jacobian`, `approx_hessian`, `hessian_from_grad`, `complex_step_grad`, `check_grad` |
| Test problems         | `problems::{rosen, rosen_grad, rosen_hess, rosen_hessp, rosenbrock, booth, beale, himmelblau, powell_singular, wood, sphere, rastrigin, ackley}` |

Methods: line searches by More-Thuente (MINPACK-2 dcsrch), Nocedal-Wright
strong Wolfe zoom and Armijo backtracking; BFGS with a scaled first
estimate; L-BFGS by the two-loop recursion; Polak-Ribiere+ and
Fletcher-Reeves CG with restarts; truncated Newton-CG with the forcing
sequence min(0.5, sqrt(|g|)); trust regions with dogleg (Hessian shifted
to positive definite when needed) and Steihaug CG; L-BFGS-B by Byrd, Lu,
Nocedal and Zhu (generalized Cauchy point, subspace minimization on the
compact representation); SPG for boxes; the PHR augmented Lagrangian with
L-BFGS-B inside; a two-phase dense simplex with Bland's rule after
degenerate runs and Mehrotra's predictor-corrector for LPs and QPs;
Levenberg-Marquardt with More's scaling and Nielsen's damping on a QR of
the damped system; trust-region reflective with Coleman-Li scaling as in
SciPy; Powell's hybrid dogleg with Broyden updates; best1bin differential
evolution with a Latin hypercube start; basin hopping with an adaptive
step; fast simulated annealing. Each function's docs give the method and
its reference.

## Docs

https://packages.nabi-lang.org/packages/optimize/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
