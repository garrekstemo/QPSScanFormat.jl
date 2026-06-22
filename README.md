# QPSScanFormat.jl

Canonical reader and writer for the **QPSDrive HDF5 scan format**.

This package is the single source of truth for the on-disk schema of scan
results produced by QPSDrive / QPSConsole. It owns:

- The format spec (`docs/hdf5-format.md`)
- `Loaded*` result types returned by the reader
- `save_scan` / `load_scan` and supporting helpers
- Schema constants (`FORMAT_VERSION`, attribute and group names)

It deliberately depends only on `HDF5`, `Dates`, and `Statistics`.
No analysis stack, no instrument drivers, no Makie — so any consumer
(including the headless instrument server) gets the format layer without
lab-only or analysis dependencies.

`Loaded*` results are **plain data**: Float64 vectors/matrices bundled as
NamedTuples (`trace = (time, signal)`, `spectrum = (wavenumber, signal)`,
`sweeps = (X, Y, DC)`; broadband loads as a `(time, wavelength, data)`
NamedTuple). Analysis typing lives upstream — load through QPSTools to get
OpticalSpectroscopy types (`KineticTrace`, `Spectrum`, `TimeResolvedMatrix`, `SweepData`)
wrapped in the same `Loaded*` structs. Writers are duck-typed on the same
field names, so producers may pass either NamedTuples or
OpticalSpectroscopy containers.

## Position in the ecosystem

```
QPSScanFormat (schema + read + write + Loaded* plain-data types)
    │
    ├── QPSDrive (writes files during scans)
    ├── QPSTools (wraps load_scan results into OpticalSpectroscopy types for analysts)
    └── QPSLab/server (opens scan files into projects, via QPSTools' typed wrapper)
```

## Quick start

```julia
using QPSScanFormat

result = load_scan("scan_001.h5")  # returns the appropriate Loaded* type
# scan_type attribute on the file picks the dispatch

result.trace.time     # Vector{Float64}
result.trace.signal   # Vector{Float64}
```

Analysts working in the REPL should prefer `using QPSTools` and its
`load_scan`, which returns the same `Loaded*` results carrying
`KineticTrace`/`Spectrum` objects ready for fitting and plotting.

See `docs/hdf5-format.md` for the on-disk schema.
