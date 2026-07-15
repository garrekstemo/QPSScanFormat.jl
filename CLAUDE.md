# QPSScanFormat.jl

The canonical HDF5 scan-file layer of the lab spectroscopy stack (see global
CLAUDE.md ecosystem map). Owns the on-disk schema for QPSDrive scan files plus
the reader and writers.

## Scope

In scope: the HDF5 schema (`docs/hdf5-format.md`), `load_scan` and the typed
`Loaded*` results, the `save_*_scan` writers, in-place metadata editors
(`update_scan_*!`), and schema constants.

**No analysis dependencies.** The OpticalSpectroscopy dependency was
deliberately dropped: readers return **plain data** — `(time, signal)`, `(wavenumber, signal)`, `(X, Y, DC)` NamedTuples and a
bare `(time, wavelength, data)` broadband NamedTuple. The analysis types
(`KineticTrace`, `Spectrum`, `TimeResolvedMatrix`, `SweepData`) are attached one
layer up by QPSTools' own `load_scan`, never here.

**Writers are duck-typed.** `save_*_scan` accepts any object with the right
fields (e.g. a `(time, signal)` NamedTuple, or QPSDrive's scan structs) — there
is no dependency on the producer's types.

## Storage conventions

- Wavelength (`wavelength_nm`) is the canonical *stored* spectral axis. Wavenumber
  is **not** stored; the reader computes it (`10⁷ / λ_nm`) and surfaces the
  spectrum payload as a `(wavenumber, signal)` NamedTuple for convenience. Legacy
  files storing `wavenumber_cm` are read back to wavelength symmetrically.
- Raw per-sweep X/Y/DC are stored; analysis quantities (R, θ, ΔOD) are computed
  downstream.
- Format tag `QPSDrive/<major>.<minor>`: a future major version errors, a future
  minor warns.

## Dependencies

`HDF5`, `Dates`, `Statistics` only. Keep it that way — adding an analysis
dependency re-couples the format layer to the analysis layer.

## Development

- Not yet registered (URL-pinned by QPSTools via `[sources]`).
- Tests use synthetic in-memory fixtures and `mktempdir` round-trips — no local
  file dependencies.
