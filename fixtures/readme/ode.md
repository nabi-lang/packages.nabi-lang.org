# ode

Differential equations for Nabi, on core's `Array`: adaptive initial value
solvers (Bogacki-Shampine, Dormand-Prince, DOP853, Radau IIA, variable-order
BDF, the Rosenbrock method RODAS, and automatic stiff / non-stiff switching)
with dense output and event location, fixed-step Runge-Kutta methods,
symplectic integrators for Hamiltonian systems (Verlet, leapfrog, Yoshida
4 and 6), and boundary value problems by 4th order collocation with mesh
refinement. Pure Nabi, so it runs on every target, wasm included.

## Add it

```sh
nabi add ode
```

Needs Nabi 0.1 or later. It depends on `linalg` (the Newton systems of the
implicit methods).

## Usage

The right-hand side is a closure of `(t, y)`; the time span is a range,
which may run backwards. Options are named arguments.

```nabi
use ode::{Direction, Event, Method};
use core::array::Vector;

// y'' = -y: y = sin t.
let f = |t: f64, y: Vector<f64>| -> Vector<f64> { [y[1], -y[0]] };
let y0: Vector<f64> = [0.0, 1.0];
let r = try ode::solve_ivp(f, 0.0..10.0, y0, method: Method::Dop853, rtol: 1e-10, atol: 1e-12);
assert((r.last()[0] - 10.0f64.sin()).abs() < 1e-8);

// Dense output anywhere on the span: call it at a time or a vector of them.
let ys = (r.sol)([0.5, 1.5, 2.5]);                        // [n, 3]
let sol = r.sol;
assert((sol(1.234)[0] - 1.234f64.sin()).abs() < 1e-8);

// Zero crossings, here the falling ones only; a terminal event stops the run.
let down = Event { f: |t: f64, y: Vector<f64>| -> f64 { y[0] }, direction: Direction::Falling };
let e = try ode::solve_ivp(f, 0.0..10.0, y0, events: [down], rtol: 1e-10, atol: 1e-12);
assert((e.t_events[0][0] - 3.141592653589793).abs() < 1e-8);
```

`r.t` and `r.y` hold the step ends (or the `t_eval` times) with the state
as columns, `r.status` says why the run stopped, and `nfev`, `njev`, `nlu`
count the work. Bad input throws `OdeError`; a run that cannot finish
returns what it has with a failing status.

Stiff problems want an implicit method; give the Jacobian if you have it:

```nabi
use ode::{Jacobian, Method};

let p = ode::problems::van_der_pol(1000.0);
let r = try ode::solve_ivp(p.f, p.span, p.y0, method: Method::Radau, rtol: 1e-6, atol: 1e-6, jac: Jacobian::Exact(p.jac));
let a = try ode::solve_ivp(p.f, p.span, p.y0, method: Method::Auto, rtol: 1e-6, atol: 1e-6);
println(f"Radau {r.nfev} evaluations, Auto {a.nfev} with {a.switches.len()} switches");
```

Fixed-step and symplectic integrators:

```nabi
use ode::Symplectic;
use core::array::Vector;

// Kepler orbit, e = 0.5: the energy error of Yoshida's method stays bounded.
let (force, q0, p0, energy) = ode::problems::kepler(0.5);
let o = try ode::symplectic(|p: Vector<f64>| -> Vector<f64> { p }, force, q0, p0, 0.0..628.3, 100000, method: Symplectic::Yoshida4, every: 100);
let e = o.energy(energy);
assert((e[e.len() - 1] + 0.5).abs() < 1e-6);

let y0: Vector<f64> = [1.0];
let s = try ode::rk4(|t: f64, y: Vector<f64>| -> Vector<f64> { y }, 0.0..1.0, y0, 100);
assert((s.last()[0] - 1.0f64.exp()).abs() < 1e-9);
```

Boundary value problems take a mesh and a guess, one column per node:

```nabi
use core::array::{Array, Matrix, Vector};

// Bratu's problem y'' + e^y = 0, y(0) = y(1) = 0.
let x: Vector<f64> = [0.0, 0.25, 0.5, 0.75, 1.0];
let y: Matrix<f64> = Array::zeros([2, 5]);
let b = try ode::solve_bvp(|x: f64, y: Vector<f64>| -> Vector<f64> { [y[1], -y[0].exp()] }, |ya: Vector<f64>, yb: Vector<f64>| -> Vector<f64> { [ya[0], yb[0]] }, x, y, tol: 1e-8);
assert(b.success() && (b.sol.at(0.5)[0] - 0.1405392144).abs() < 1e-8);
```

`solve_bvp_params` adds unknown parameters (eigenvalue problems).

## Notation

With the `ops` feature (on by default), `ode::ops::Flow` is a one-step map
`phi_h`, and splitting and composition methods read as they are written in
the literature: `a ∘ b` (core's composition) applies `b`, then `a`; `c *
a` scales the step; `a ** n` takes `n` steps; `phi ⊳ y` applies a flow to
a state (it binds like `*`, so `a ∘ b ⊳ y` is `(a ∘ b) ⊳ y`).

```nabi
use ode::ops::{Advance, Flow};
use core::array::Vector;

let (force, q0, p0, _) = ode::problems::kepler(0.5);
let kick = Flow::kick(force, 2, 0.01);                           // p += h F(q)
let drift = Flow::drift(|p: Vector<f64>| -> Vector<f64> { p }, 2, 0.01);   // q += h p
let verlet = (0.5 * kick) ∘ drift ∘ (0.5 * kick);                 // Strang splitting
let c = 2.0f64.cbrt();
let yoshida = (1.0 / (2.0 - c) * verlet) ∘ (-c / (2.0 - c) * verlet) ∘ (1.0 / (2.0 - c) * verlet);
let s1 = yoshida ** 100 ⊳ [q0[0], q0[1], p0[0], p0[1]];
```

`⊳` is registered by this package; build without the feature
(`default_features: false`) if it clashes with another package's.

## What is in it

| Area              | Items                                                                 |
|-------------------|-----------------------------------------------------------------------|
| Initial values    | `solve_ivp` (`Method::Rk23`, `Rk45`, `Dop853`, `Radau`, `Bdf`, `Rodas`, `Auto`), `Jacobian`, `Event`, `Direction`, `Solution`, `Status`, `Dense` |
| Fixed step        | `fixed` (`Fixed::Euler`, `Midpoint`, `Heun`, `Rk4`), `euler`, `rk4`   |
| Hamiltonian       | `symplectic` (`Symplectic::Euler`, `Verlet`, `Leapfrog`, `Yoshida4`, `Yoshida6`), `verlet`, `leapfrog`, `yoshida4`, `Orbit` |
| Boundary values   | `solve_bvp`, `solve_bvp_params`, `Bvp`, `BvpStatus`                   |
| Test problems     | `problems::robertson`, `van_der_pol`, `hires`, `oregonator`, `lorenz`, `kepler`, `gravity` |
| Notation (`ops`)  | `Flow` (`∘`, `*`, `**`), `Advance` (`⊳`)                              |

Methods: the explicit pairs with local extrapolation and Hairer's step
control and starting step, Shampine's 4th order interpolant for RK45 and
Hairer's 7th degree one for DOP853; Radau IIA (RADAU5) with its stage
system split into one real and one complex LU and Gustafsson's predictive
step control; BDF in the quasi-constant step NDF form of ode15s, orders 1
to 5; RODAS (Hairer-Wanner) with its 3rd order dense output; `Auto`
starts with RK45 and moves to BDF on Hairer's stiffness test, and back
when an explicit step of the current size is stable; events by Brent's
method on the dense output; BVPs by the Kierzenka-Shampine collocation
with damped Newton (banded LU for separated boundary conditions) and
residual-driven refinement. The adaptive solvers follow SciPy's
`solve_ivp` / `solve_bvp` closely and take the same number of steps on
the same problems. Jacobians are by forward differences unless given.

Not in 0.1.0: delay differential equations, sparse or banded Jacobians
for large stiff systems, a vectorized right-hand side, user Jacobians for
`solve_bvp`, and DAEs (mass matrices).

## Docs

https://packages.nabi-lang.org/packages/ode/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
