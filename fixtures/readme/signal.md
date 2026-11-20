# signal

Signal processing for Nabi, in pure Nabi over `core::array` arrays: FFTs
of any length (mixed radix, Bluestein for large primes, real and n-d, DCT and
DST), convolution and correlation (direct, FFT, overlap-add, 2-d), windows, FIR
and IIR filter design (Butterworth, Chebyshev I and II, Bessel, as second-order
sections), causal and zero-phase filtering, frequency response, resampling,
Welch spectra, STFT and spectrograms, the analytic signal and peak finding. The
API and defaults follow SciPy's `scipy.signal` and `scipy.fft`, so a SciPy
recipe carries over.

## Add it

```sh
nabi add signal
```

Needs Nabi 0.1 or later. No C libraries: every target works, wasm included.

## Usage

```nabi
use core::array::{Array, Vector};
use signal::filter::{Band, butter, sosfiltfilt};

// A 50 Hz tone in noise, sampled at 1 kHz.
let fs = 1khz;
let x = Array::from_fn([2000], |i: [usize; 1]| -> f64 {
    let t = (i[0] as f64) / fs;
    (2.0 * f64::PI * 50hz * t).sin() + 0.3 * (2.0 * f64::PI * 300hz * t).sin()
});

// Spectrum of the detrended signal: the strongest bin.
let s = try x |> signal::filter::detrend |> signal::welch(fs: fs, nperseg: 500);
println(s.peak()); // 50

// Zero-phase low-pass at 100 Hz: no delay, the 300 Hz tone gone.
let sos = try butter(6, Band::Lowpass(100hz), fs: fs);
let y = try sosfiltfilt(sos, x);

// Convolution reads as math: `⊛` convolves, `⋆` correlates.
let k: Vector<f64> = [0.25, 0.5, 0.25];
let smooth = x ⊛ k;
```

`10hz`, `8khz`, `5ms` and `20us` are plain `f64` numbers in hertz and seconds,
from the `units` module. `a ⊛ b` (U+229B) and `a ⋆ b` (U+22C6) are full
convolution and correlation at the level of `*`, from `ops`. Errors are
`SignalError`s that say what to pass instead:

```nabi
use signal::filter::{Band, butter};

try butter(4, Band::Lowpass(100.0)) catch e {
    println(e); // `butter` band edge: got 100, need 0 < edge < fs / 2 = 1 (edges are in units of fs; pass `fs:` with your sampling rate)
};
```

## What is in it

| Module | Contents |
|---|---|
| `fft` | `fft`, `ifft`, `rfft`, `irfft`, `fftn`, `ifftn`, `fft2`, `ifft2`, `rfftn`, `irfftn`, `Plan`, `RealPlan`, `Norm`, `dct`, `idct`, `dst`, `idst`, `fftfreq`, `rfftfreq`, `fftshift`, `ifftshift`, `next_fast_len` |
| `conv` | `convolve`, `correlate`, `convolve2d`, `correlate2d`, `correlation_lags`, `Mode`, `Method` |
| `window` | `hann`, `hamming`, `blackman`, `bartlett`, `kaiser`, `kaiser_beta`, `tukey`, `gaussian`, `Window`, `get` |
| `filter` | `Band`, `firwin`, `butter`, `cheby1`, `cheby2`, `bessel`, `iirfilter`, `Zpk`, `sos_to_ba`, `lfilter`, `lfilter_state`, `lfilter_zi`, `sosfilt`, `sosfilt_state`, `sosfilt_zi`, `filtfilt`, `sosfiltfilt`, `freqz`, `sosfreqz`, `Response`, `resample`, `decimate`, `detrend` |
| `spectral` | `welch`, `periodogram`, `Spectrum`, `Scaling`, `stft`, `istft`, `spectrogram`, `hilbert`, `envelope` |
| `peaks` | `find_peaks`, `Peaks` |
| `ops` | `⊛` (`Convolve`), `⋆` (`Correlate`) |
| `units` | `hz`, `khz`, `mhz`, `ms`, `us` number suffixes |

A real signal is anything `linalg::AsVector<f64>` takes: a `Vector` or
`List` of `f64`, `f32` or integers, a fixed array, a range. Complex ones are
`Vector<Complex<f64>>`. `signal::complex`, `real`, `imag`, `abs` and `angle`
convert between them.

## Accuracy and speed

Transforms are accurate to about `1e-15 * log2(n)` relative (`ifft(fft(x))`
returns `x` to `1e-12` for every length tested, primes to 65537 included);
every twiddle factor is computed on its own, never by recurrence. IIR filters
are designed and run as second-order sections, which stay accurate at high
orders. On an Apple M-series core a complex FFT of 2^16 points takes about
1.6 ms, a real one 1.0 ms. Large n-d transforms and convolutions split their
work over `par` workers.

## Docs

https://packages.nabi-lang.org/packages/signal/latest/docs

## License

Licensed under either of [MIT](LICENSE-MIT) or [Apache-2.0](LICENSE-APACHE), at
your option.
