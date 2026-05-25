# HDF5 Scan File Format — QPSDrive/1.0

Self-describing file format for pump-probe and photoluminescence scan results.
Each file is a complete record of one measurement: raw per-sweep multi-channel
data, averaged statistics, full instrument state, and scan parameters.

## Design Principles

1. **Store raw measurements, defer analysis.** Per-sweep X and Y from the
   lock-in are the irreplaceable data. Derived quantities (R, theta, delta_OD,
   wavenumber) are computed by downstream tools (QPSTools, QPSLab).

2. **Wavelength is the canonical spectral axis.** The monochromator sets
   wavelength in nm. Wavenumber is a derived quantity with non-uniform spacing.

3. **Per-sweep storage enables post-hoc quality control.** Outlier rejection,
   drift detection, and proper error bars require individual sweep data.

4. **Metadata travels with the data.** No separate parameter files to lose.

## Scan Types

| `scan_type` | Independent axis | Fixed parameter | Use case |
|-------------|-----------------|-----------------|----------|
| `kinetic`   | `time_ps`       | wavelength      | Pump-probe kinetics, TRPL |
| `spectral`  | `wavelength_nm` | delay           | PL spectrum, absorption |
| `composite` | both            | —               | TA matrix, PLE |

The `measurement_type` attribute distinguishes the physical measurement
(pump_probe, photoluminescence, absorption, etc.) from the scan geometry.

## File Structure

```
/                                        Root group
├── format          = "QPSDrive/1.0"     Format identifier
├── scan_type       = "kinetic"          Scan geometry
├── measurement_type = "pump_probe"      Physical measurement
├── timestamp       = "2026-03-11T..."   ISO 8601, scan start
├── description     = "..."              User description
├── duration_seconds = 142.5             Wall-clock elapsed time
│
├── instrument_state/                    Snapshot at scan start
│   ├── stage/                           Attributes: position_mm, delay_ps, ...
│   ├── monochromator/                   Attributes: wavelength_nm, grating_steps, ...
│   └── detector/                        Attributes: time_constant_s, signal_mode, ...
│
├── calibration/                         Attributes (may be absent)
│   ├── t0_ps        = 142.5            Time-zero reference (NaN if not set)
│   └── ps_per_mm    = 6.6713           Stage delay conversion factor
│
├── scan/                                Scan configuration
│   ├── averages     = 100               Readings averaged per point per sweep
│   ├── settle_time_s = 0.3              Wait after instrument move
│   ├── n_sweeps     = 10                Completed sweeps
│   ├── direction    = "unidirectional"  Scan direction
│   ├── wavelength_nm = 5000.0           Fixed wavelength (kinetic only)
│   ├── delay_ps     = 1.5              Fixed delay (spectral only)
│   └── metadata/                        User key-value pairs
│
└── data/                                Measurement data
    ├── time_ps[N]                       Scan axis (kinetic & composite)
    ├── wavelength_nm[M]                 Scan axis (spectral & composite)
    │
    ├── sweeps/                          Raw per-sweep data
    │   ├── 001/
    │   │   ├── X[N]                     In-phase signal
    │   │   ├── Y[N]                     Quadrature signal
    │   │   └── DC[N]                    Probe DC level
    │   ├── 002/
    │   │   ├── X[N]
    │   │   ├── Y[N]
    │   │   └── DC[N]
    │   └── ...
    │
    ├── X_mean[N]                        Mean of X across sweeps
    ├── X_std[N]                         Std dev of X across sweeps
    ├── Y_mean[N]                        Mean of Y across sweeps
    └── DC_mean[N]                       Mean of DC across sweeps
```

## Channel Definitions

| Channel | Description | Source |
|---------|-------------|--------|
| X       | In-phase (signal) component from lock-in demodulator | MFLI demod X |
| Y       | Quadrature component — diagnostic for phase drift | MFLI demod Y |
| DC      | Probe beam DC level for normalization (0 if unavailable) | Aux input or 0 |

R (magnitude) and theta (phase) are derived: `R = sqrt(X^2 + Y^2)`,
`theta = atan(Y, X)`. They are not stored.

## Composite Scans (TA Matrix)

For composite scans, the signal arrays are 2D: `X_mean[N_time, M_wavelength]`.
Each sweep group contains 2D arrays with the same shape. Both `time_ps` and
`wavelength_nm` axes are present.

## Noise Characterization

Noise scans (`scan_type = "noise"`) have a different structure and are not
covered by this spec. They are diagnostic measurements, not experiment results.

## Notes

- **NaN values**: Unmeasured points (from scan abort) contain NaN. Consumers
  should use NaN-aware statistics.
- **Sweep numbering**: Zero-padded three-digit labels (`001`, `002`, ...).
  Sorted lexicographically on load.
- **Backward compatibility**: New fields may be added. Readers should check
  `haskey` before accessing optional groups (calibration, sweeps).
- **Atomic writes**: Files are written to a `.tmp` path and renamed on
  completion to prevent corruption from crashes.
