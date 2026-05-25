# QPSScanFormat.jl

Canonical reader and writer for the **QPSDrive HDF5 scan format**.

This package is the single source of truth for the on-disk schema of scan
results produced by QPSDrive / QPSConsole. It owns:

- The format spec (`docs/hdf5-format.md`)
- `Loaded*` result types returned by the reader
- `save_scan` / `load_scan` and supporting helpers
- Schema constants (`FORMAT_VERSION`, attribute and group names)

It deliberately depends only on `HDF5`, `Dates`, `Statistics`, and
`SpectroscopyTools` (for `TATrace`, `TASpectrum`, `TAMatrix`, `SweepData`).
No instrument drivers, no PyCall, no Makie — so analysis users at any laptop
can install it without lab-only dependencies.

## Position in the ecosystem

```
SpectroscopyTools (pure data types)
    │
    └── QPSScanFormat (schema + read + write + Loaded* types)
           │
           ├── QPSDrive (writes files during scans)
           ├── QPSTools (re-exports load_scan for analysts)
           └── QPSLab/server (opens scan files into projects — future)
```

## Quick start

```julia
using QPSScanFormat

result = load_scan("scan_001.h5")  # returns the appropriate Loaded* type
# scan_type attribute on the file picks the dispatch
```

See `docs/hdf5-format.md` for the on-disk schema.
