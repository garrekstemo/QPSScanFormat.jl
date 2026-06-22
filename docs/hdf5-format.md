# HDF5 Scan File Format — QPSDrive/1.0

Self-describing file format for pump-probe and photoluminescence scan results.
Each file is a complete record of one measurement: raw per-sweep multi-channel
data, averaged statistics, full instrument state, and scan parameters.

This document describes what QPSScanFormat.jl actually writes and reads
(`src/schema.jl`, `src/write.jl`, `src/read.jl`). The implementation is
canonical: QPSDrive writes through `save_*_scan` and QPSLab/QPSTools read
through `load_scan`, so the code and this spec are kept in lockstep.

`Loaded*` results returned by `load_scan` are plain data (Float64
vectors/matrices in NamedTuples); analysis typing lives upstream, where
QPSTools wraps the same results in OpticalSpectroscopy types.

## Design Principles

1. **Store raw measurements, defer analysis.** Per-sweep X and Y from the
   lock-in are the irreplaceable data. Analysis quantities (R, theta, delta_OD)
   are computed by downstream tools (QPSTools, QPSLab).

2. **Wavelength is the canonical *stored* spectral axis.** The monochromator sets
   wavelength in nm, and only `wavelength_nm` is written to disk. Wavenumber is a
   trivial reciprocal (`10⁷ / λ_nm`, non-uniform spacing) — not stored, but the
   reader computes it on read and surfaces the spectrum payload as a
   `(wavenumber, signal)` NamedTuple for convenience. (Legacy files that stored
   `wavenumber_cm` instead are read back to wavelength symmetrically.)

3. **Per-sweep storage enables post-hoc quality control.** Outlier rejection,
   drift detection, and proper error bars require individual sweep data.

4. **Metadata travels with the data.** No separate parameter files to lose.

## Format Versioning

The root `format` attribute is `"QPSDrive/<major>.<minor>"` (currently
`"QPSDrive/1.0"`, from `FORMAT_VERSION` in `src/schema.jl`). Semver-style
policy, enforced by `load_scan` on every read:

| File's `format` attribute | Reader behavior |
|---------------------------|-----------------|
| Missing | Error: not a QPSDrive scan file |
| Not of the form `QPSDrive/<major>.<minor>` | Error: unrecognized producer |
| Major version > supported | Error naming both versions (upgrade the reader) |
| Same major, minor > supported | Warning; file loads (minor bumps are additive) |
| Same major, minor ≤ supported | Loads silently |

Writers bump the **minor** version when adding fields or groups that old
readers can safely ignore, and the **major** version for any change that
alters the meaning or layout of existing data.

## Scan Types

| `scan_type` | Independent axis | Fixed parameter | Use case |
|-------------|------------------|-----------------|----------|
| `kinetic`   | `time_ps`        | wavelength      | Pump-probe kinetics, TRPL |
| `spectrum`  | `wavelength_nm`  | delay           | PL spectrum, absorption |
| `composite` | both, per sub-scan | —             | N spectra + M kinetic traces in one file |
| `broadband` | `time_ps` × `wavelength_nm` | —    | TA matrix (array detector) |
| `noise`     | `time_constants` | —               | Detector noise characterization, Allan deviation |

Legacy files with `scan_type = "spectral"` are accepted on read and treated
as `spectrum`.

`load_scan` returns, respectively: `LoadedScanResult`, `LoadedSpectralResult`,
`LoadedCompositeResult`, a bare `(time, wavelength, data)` NamedTuple
(broadband metadata is stored on disk but not currently surfaced by the
reader), and `LoadedNoiseResult`.

## Root Attributes (all scan types)

```
/
├── format           = "QPSDrive/1.0"    Format identifier (see versioning above)
├── scan_type        = "kinetic"         One of the five values above
├── timestamp        = "2026-03-11T..."  ISO 8601, scan start
├── description      = "..."             Short user description
├── comment          = "..."             Free-form comment (may be empty;
│                                        missing in old files, read as "")
└── duration_seconds = 142.5             Wall-clock elapsed time (Float64)
```

There is no `measurement_type` root attribute. Producers that need to record
the physical measurement kind (pump_probe, photoluminescence, ...) do so as a
key in the `scan/` group.

## Common Groups

### `instrument_state/`

Snapshot of every instrument at scan start. One sub-group per instrument;
each instrument's settings are attributes on its sub-group:

```
instrument_state/
├── stage/            Attributes: position_mm, delay_ps, ...
├── monochromator/    Attributes: wavelength_nm, grating_steps, ...
└── detector/         Attributes: time_constant_s, signal_mode, ...
```

Attribute value marshalling (applies everywhere attributes are written):
strings stored as-is; `Bool` stored as `Int` (0/1); integers as `Int`;
floats as `Float64`; `nothing` is **omitted** (absence is the in-band signal
for "unset"); anything else is stringified.

### `scan/`

Scan configuration, stored as attributes from a flat producer-supplied dict.
Keys are producer-defined; typical entries:

```
scan/
├── averages      = 100              Readings averaged per point per sweep
├── settle_time_s = 0.3              Wait after instrument move
├── n_sweeps      = 10               Completed sweeps
├── wavelength_nm = 5000.0           Fixed wavelength (kinetic)
├── delay_ps      = 1.5              Fixed delay (spectrum)
└── metadata/                        User key-value pairs (sub-group attrs,
                                     e.g. sample_name)
```

The reserved key `"metadata"` (a nested dict) becomes the `scan/metadata`
sub-group; all other keys are flat attributes on `scan/`.

## Per-Sweep Data Block

Wherever per-sweep data is stored (single-scan `data/`, or a composite
sub-group), the layout is:

```
├── sweeps/                 Raw per-sweep data
│   ├── 001/
│   │   ├── X[N]            In-phase signal
│   │   ├── Y[N]            Quadrature signal
│   │   └── DC[N]           Probe DC level
│   ├── 002/ ...
├── X_mean[N]               NaN-aware mean of X across sweeps
├── X_std[N]                NaN-aware sample std of X (0.0 where <2 finite values)
├── Y_mean[N]               NaN-aware mean of Y
└── DC_mean[N]              NaN-aware mean of DC
```

When a scan has **no** per-sweep data, only `X_mean[N]` is written (the
producer's mean signal directly).

**Mean-signal resolution on read** (`_read_mean_signal`): if `sweeps/` is
present, use `X_mean` if it exists, else recompute the NaN-aware mean of the
sweep X matrix; if `sweeps/` is absent, use the legacy `signal` dataset if
present, else `X_mean`.

## Channel Definitions

| Channel | Description | Source |
|---------|-------------|--------|
| X       | In-phase (signal) component from lock-in demodulator | MFLI demod X |
| Y       | Quadrature component — diagnostic for phase drift | MFLI demod Y |
| DC      | Probe beam DC level for normalization (0 if unavailable) | Aux input or 0 |

R (magnitude) and theta (phase) are derived: `R = sqrt(X^2 + Y^2)`,
`theta = atan(Y, X)`. They are not stored.

## Per-Type `data/` Layout

### `kinetic`

```
data/
├── time_ps[N]              Scan axis
└── <per-sweep block>       sweeps/ + stats, or X_mean alone
```

### `spectrum`

```
data/
├── wavelength_nm[M]        Canonical scan axis
└── <per-sweep block>
```

Wavenumber is derived on read as `1e7 / wavelength_nm`. Legacy files that
stored only `wavenumber_cm` are accepted; wavelength is then derived as
`1e7 / wavenumber_cm`.

### `broadband`

```
data/
├── time_ps[N]
├── wavelength_nm[M]
└── signal[N, M]            TA matrix, rows = time points, cols = wavelengths
```

Dimensions are as seen from Julia (column-major). C-order tools (`h5dump`,
h5py) report the dimensions reversed (`[M, N]`).

Broadband files write `instrument_state/` only when non-empty, and `scan/`
only as `scan/metadata` (when a metadata dict is supplied). The reader
currently returns only the `(time, wavelength, data)` matrix payload; the
stored attributes are not yet surfaced through `load_scan`.

### `composite`

N spectra plus M kinetic traces sharing the root description, comment, and
instrument state. Either sub-group may be absent, but the writer rejects a
composite with both empty.

```
data/
├── spectra/                          Present iff N ≥ 1
│   ├── spectrum_001/
│   │   ├── wavelength_nm[M]
│   │   ├── wavenumber_cm[M]          Stored explicitly (unlike single spectrum files)
│   │   ├── signal[M]                 Mean signal, always stored
│   │   ├── <per-sweep block>         Only when per-sweep data exists
│   │   └── attrs: description, comment, timestamp, duration_seconds,
│   │              delay_ps (optional)
│   ├── spectrum_002/ ...
└── kinetics/                         Present iff M ≥ 1
    ├── trace_001/
    │   ├── time_ps[N]
    │   ├── <per-sweep block>         sweeps/ + stats, or X_mean alone
    │   └── attrs: description, comment, timestamp, duration_seconds,
    │              wavelength_nm (optional)
    ├── trace_002/ ...
```

On read, each sub-scan's `scan_params` dict carries its optional fixed
parameter (`delay_ps` / `wavelength_nm`) and a `sub_path` key (e.g.
`"data/spectra/spectrum_001"`) so in-place attribute rewrites can target the
exact group.

### `noise`

```
data/
├── time_constants[K]
├── noise_rms[K]
├── noise_mean[K]
├── samples[K]
├── allan_taus[L]
├── allan_devs[L]
└── statistics/             Optional; summary stats as Float64 attributes
```

## Write / Rewrite Semantics

- **Initial writes are atomic.** Every `save_*_scan` writes to `<path>.tmp`
  and renames onto the final path (same-directory rename), so a crash during
  a save cannot leave a half-written scan file at the destination.
- **In-place rewrites are NOT atomic.** `update_scan_description!`,
  `update_scan_comment!`, and `update_scan_sample_name!` (`src/rewrite.jl`)
  open the existing file in `r+` mode, delete the target attribute, and write
  the new value in place. There is a window where the attribute is deleted
  but not yet rewritten, and HDF5 has no journaling — a crash or power loss
  mid-rewrite can corrupt file metadata. Do not run these against the only
  copy of irreplaceable data without a backup.

## Notes

- **NaN values**: Unmeasured points (from scan abort) contain NaN. Consumers
  should use NaN-aware statistics; the stored `*_mean`/`*_std` datasets
  already are.
- **Sweep and sub-scan numbering**: Zero-padded three-digit labels starting
  at 001 (`001`, `002`, ...; `spectrum_001`, `trace_001`, ...). Sorted
  lexicographically on load, which assumes ≤ 999 entries.
- **Backward compatibility on read**: legacy `scan_type = "spectral"` maps to
  `spectrum`; a missing `comment` attribute reads as `""`; the legacy
  `signal` dataset is honored by the mean-signal fallback chain above.
- **Error reporting**: `load_scan` validates the `format` attribute first and
  wraps raw HDF5 failures (truncated/corrupt files, missing datasets) in
  informative `ErrorException`s naming the file.
- **Reserved, unimplemented**: an earlier draft of this spec defined a root
  `calibration/` group (`t0_ps`, `ps_per_mm`). It was never implemented —
  nothing writes or reads it. The name is reserved for a future minor
  version; producers should keep calibration values in `scan/` for now.
