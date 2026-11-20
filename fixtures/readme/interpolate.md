# interpolate

Interpolation, splines, smoothing and integration of data for Nabi, on
core's `Array`: linear, step, barycentric polynomial, PCHIP, Akima and
cubic splines in 1-d; B-splines with derivatives, integrals, roots and
FITPACK-style smoothing; multilinear and tensor-product spline
interpolation on grids of any rank; Delaunay triangulation, k-d trees and
radial basis functions for scattered data; smoothing splines,
Savitzky-Golay and LOWESS; polynomials and Chebyshev series; quadrature of
samples and functions (adaptive Gauss-Kronrod with an error estimate) and
numerical differentiation. Pure Nabi, so it runs on every target, wasm
included.

## Add it

```sh
nabi add interpolate
```

Needs Nabi 0.1 or later. It depends on `linalg` and `autodiff`.

## Usage

Every interpolant is called like the function it is: `s(x)` at a point,
`s(xs)` at every element of an array of any rank (also `xs |> s` and
`s.(xs)`). A 1-d one is a `Curve`, with `at(x)` and `eval(xs)` by name
and `func()` for a plain `fn(f64) -> f64`. Sample points are anything
`linalg::AsVector<f64>` takes: a `Vector`, a `List` (of floats or
integers), a fixed array, a range.

```nabi
use interpolate::{Boundary, Extrapolate};
use core::array;
use core::array::Vector;

let x = 0..5;
let y = [0, 1, 0, 1, 0];

let s = try interpolate::cubic_spline(x, y);              // not-a-knot, C2
let p = try interpolate::pchip(x, y);                     // monotone, no overshoot
let n = try interpolate::cubic_spline_with(x, y, Boundary::Natural);
let xs: Vector<f64> = array::linspace(0.0, 4.0, 9);
let ys = s(xs);                                           // = xs |> s
let area = s.integrate(0.0..4.0);
let peaks = s.derivative(1).roots();                      // the extrema
let flat = p.extrapolate(Extrapolate::Clamp)(9.0);        // 0.0
println(f"{ys:?} {area} {peaks:?} {flat} {n(0.5)}");
```

B-splines of any degree, interpolating or smoothing (FITPACK's `splrep`:
the fewest knots whose residual sum is at most `s`):

```nabi
use core::array;
use core::array::Vector;

let x: Vector<f64> = array::linspace(0.0, 10.0, 101);
let y = f64::sin.(x) .+ 0.05 .* f64::cos.(x .* 41.0);
let b = try interpolate::splrep(x, y, s: 0.15);           // cubic smoothing spline
let q = try interpolate::make_interp_spline(x, y, 5);     // quintic interpolant
println(f"{b.knots().len()} knots, {b(1.0)} {q.derivative(2)(1.0)}");
```

Grids of any rank, and scattered points:

```nabi
use interpolate::{GridMethod, KdTree, LinearND, Rbf};
use core::array;
use core::array::{Array, Matrix, Vector};

let a: Vector<f64> = array::linspace(0.0, 1.0, 11);
let v = Array::from_fn([11, 11, 11], |i: [usize; 3]| -> f64 { (i[0] + i[1] * i[2]) as f64 });
let g = try interpolate::grid([a, a, a], v, GridMethod::Cubic);
println(g([0.25, 0.5, 0.75]));

let pts: Matrix<f64> = [[0, 0], [1, 0], [0, 1], [1, 1], [0.5, 0.4]];
let val: Vector<f64> = [0, 1, 1, 2, 0.9];
let tri = try LinearND::new(pts, val);                    // Delaunay + barycentric
let rbf = try Rbf::new(pts, val);                         // thin-plate spline
let tree = try KdTree::new(pts);
let near = try tree.knn([0.9, 0.9], 2);
println(f"{tri([0.5, 0.5])} {rbf([0.5, 0.5])} {near.indices:?}");
```

Integration and differentiation:

```nabi
use core::array::Vector;

let r = try interpolate::quad(|x: f64| -> f64 { x.ln() / x.sqrt() }, 0.0..1.0);
println(f"{r.value} +- {r.error}");                       // -4, error ~1e-13
let g = try interpolate::quad(|x: f64| -> f64 { (-x * x).exp() }, -f64::INFINITY..f64::INFINITY);
let t: Vector<f64> = [0, 0.5, 1, 1.5, 2];
let area = try interpolate::simpson(t .* t, t);           // 8/3, exactly
let slope = try interpolate::gradient(t .* t, t);
println(f"{g.value} {area} {slope:?}");
```

Errors are one `InterpError` (`TooFewPoints`, `NotSorted`,
`LengthMismatch`, `NotFinite`, `BadArgument`, `Singular`,
`NoConvergence`); each message says what to write instead.

## Notation

With the `ops` feature (on by default), calculus reads like the math:

| Notation          | Meaning                                              | Named form                     |
|-------------------|------------------------------------------------------|--------------------------------|
| `∂(f)`, `∂(f, n)` | derivative of a spline, PPoly, Polynomial, Chebyshev, as one | `f.derivative(n)`, `f.deriv(n)` |
| `∫(f, a..b)`      | definite integral of a function or an interpolant    | `quad(f, a..b).value`          |
| `∇(a)`            | gradient of samples on a unit grid, as samples       | `gradient`, `gradient_nd`      |
| `a ≈ b`           | equal up to rounding (floats, arrays)                | `a.close(b, tol)`              |
| `s ⊗ t`           | tensor-product spline `s(x) t(y)`                    | linalg's `Kron`                |

`∂`, `∫` and `∇` are identifier characters in Nabi, so they are functions
named by the symbol, called with parentheses. `∂` and `∇` are autodiff's,
re-exported: they return the derivative in the form of what they are
given, never a value (`∂(s)(x)` is the value), and they differentiate
functions too, so `use interpolate::ops::*` sits with optimize's `ops`. `≈` is a registered
operator at the level of `==`; `⊗` is linalg's, so one token serves
matrices and splines. Ranges give integration limits (`0.0..1.0`,
`0.0..f64::INFINITY`), and `|>` pipes data through interpolants.

`Polynomial` has the arithmetic of core's operator traits, with no
feature needed: `+ - *` (also with an `f64` on either side), `/` and `%`
(polynomial division), `**`, and `∘` for composition.

```nabi
use interpolate::Polynomial;
use interpolate::ops::{Approx, ∂, ∫};

let p = Polynomial::new([1, -3, 0, 2]);                    // 1 - 3x + 2x^3
let q = Polynomial::x() - 1.0;
let r = p ∘ q * 2.0 + p ** 2;
assert(∂(p) == Polynomial::new([-3, 0, 6]));
assert(p % q == Polynomial::constant(p(1.0)));
assert(try ∫(f64::sin, 0.0..f64::PI) ≈ 2.0);
assert(try ∫(p, 0.0..1.0) ≈ 0.0);                          // exact, by `integrate`
println(f"{r}");
```

Build without the feature (`default_features: false`) if `≈` clashes with
another package's.

## What is in it

| Area            | Items                                                                 |
|-----------------|-----------------------------------------------------------------------|
| 1-d             | `linear`, `nearest`, `previous`, `next`, `step`, `barycentric`, `pchip`, `akima`, `makima`, `cubic_hermite`, `cubic_spline`, `cubic_spline_with` (`Boundary`), `PPoly`, `Extrapolate`, `Curve` |
| B-splines       | `BSpline`, `make_interp_spline`, `make_lsq_spline`, `splrep`, `splev`, `splint`, `sproot` |
| Grids           | `grid` (`GridMethod::Linear`, `Nearest`, `Cubic`), `RegularGrid`, `bilinear`, `bicubic`, `TensorSpline` |
| Scattered       | `Delaunay`, `KdTree`, `LinearND`, `NearestND`, `Rbf` (`Kernel`), `griddata`, `scatter::orient2d`, `scatter::incircle` |
| Smoothing       | `make_smoothing_spline`, `savgol_coeffs`, `savgol_filter` (`Edge`), `lowess` |
| Polynomials     | `Polynomial`, `Chebyshev`                                             |
| Integration     | `trapezoid`, `cumulative_trapezoid`, `simpson`, `romb`, `quad` (`Quad`), `romberg`, `fixed_quad`, `gauss_legendre`, `dblquad`, `tplquad`, `dblquad_over`, `tplquad_over` |
| Differentiation | `gradient`, `gradient_nd`, `differentiate`, `fd_weights`, `derivative` (`Estimate`) |

Methods: cubic splines by one banded system in the slopes (de Boor),
PCHIP after Fritsch-Carlson with Fritsch-Butland slopes, Akima (1970) and
modified Akima, barycentric Lagrange interpolation (Berrut-Trefethen),
B-splines by de Boor's algorithm with banded collocation and least
squares, smoothing by Dierckx's knot placement and penalized fit,
Delaunay by sweep-hull and edge flips (Delaunator) on Shewchuk's exact
predicates, k-d trees by median split, RBF on the saddle system with a
polynomial tail, smoothing splines by Reinsch's algorithm with GCV,
LOWESS after Cleveland (1979), polynomial roots from the balanced
companion matrix, Chebyshev series by Clenshaw and the colleague matrix,
quadrature by QUADPACK's QAGS/QAGI (Gauss-Kronrod 21/15 with the epsilon
algorithm), and finite differences by Fornberg's weights. Each function's
docs give its accuracy and cost.

## Docs

https://packages.nabi-lang.org/packages/interpolate/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
