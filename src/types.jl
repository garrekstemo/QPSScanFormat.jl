# Loaded result types returned by `load_scan`.
#
# These carry PLAIN DATA only — Float64 vectors/matrices bundled as
# NamedTuples — plus scan-output metadata. QPSScanFormat is the format
# layer: it knows the on-disk schema, not the analysis vocabulary.
# Analysis typing lives upstream: QPSTools wraps these results into
# OpticalSpectroscopy types (TATrace, TASpectrum, TAMatrix, SweepData)
# for students; QPSDrive/QPSConsole consume the plain fields directly.
#
# The structs are parametric so an upstream wrapper can rebuild them with
# richer payload types while keeping `r isa LoadedScanResult` etc. true.
# We can't reconstruct live instrument refs from a file, so
# instrument_state and scan_params are held as Dicts.

# Canonical plain payload shapes produced by this package's reader.
const TraceData = @NamedTuple{time::Vector{Float64}, signal::Vector{Float64}}
const SpectrumData = @NamedTuple{wavenumber::Vector{Float64}, signal::Vector{Float64}}
const SweepArrays = @NamedTuple{X::Matrix{Float64}, Y::Matrix{Float64}, DC::Matrix{Float64}}
const BroadbandData = @NamedTuple{time::Vector{Float64}, wavelength::Vector{Float64}, data::Matrix{Float64}}

"""
    LoadedScanResult

Result of `load_scan` for a kinetic scan file (`scan_type = "kinetic"`).

# Fields
- `trace` — `(time, signal)` NamedTuple of `Vector{Float64}`: mean X signal over time
- `sweeps` — `(X, Y, DC)` NamedTuple of `Matrix{Float64}` with per-sweep raw data, or `nothing` for legacy files
- `timestamp::DateTime` — when the scan started
- `duration_seconds::Float64` — elapsed wall time
- `instrument_state::Dict{String,Any}` — snapshots of each instrument at scan start
- `scan_params::Dict{String,Any}` — averages, settle_time, accumulations, metadata
- `description::String` — short human-readable scan description
- `comment::String` — long free-form comment

The payload fields are parametric: QPSScanFormat's own reader fills them
with plain NamedTuples; QPSTools rebuilds the same struct with
OpticalSpectroscopy types (`TATrace`, `SweepData`) for analysis users.
"""
struct LoadedScanResult{TR, SW}
    trace::TR
    sweeps::SW
    timestamp::DateTime
    duration_seconds::Float64
    instrument_state::Dict{String,Any}
    scan_params::Dict{String,Any}
    description::String
    comment::String
end

"""
    LoadedSpectralResult

Result of `load_scan` for a spectral scan file (`scan_type = "spectrum"`,
legacy `"spectral"` accepted). The canonical on-disk axis is
`wavelength_nm`; `wavelengths` carries those values, and `spectrum`'s
`wavenumber` field is computed from them on read.

# Fields
- `spectrum` — `(wavenumber, signal)` NamedTuple of `Vector{Float64}`
- `sweeps` — `(X, Y, DC)` NamedTuple of `Matrix{Float64}`, or `nothing`
- `wavelengths::Vector{Float64}` — canonical wavelength axis (nm)
- plus the standard metadata fields (see [`LoadedScanResult`](@ref))

Parametric payloads for the same reason as [`LoadedScanResult`](@ref):
QPSTools rebuilds with `TASpectrum`/`SweepData`.
"""
struct LoadedSpectralResult{SP, SW}
    spectrum::SP
    sweeps::SW
    wavelengths::Vector{Float64}
    timestamp::DateTime
    duration_seconds::Float64
    instrument_state::Dict{String,Any}
    scan_params::Dict{String,Any}
    description::String
    comment::String
end

"""
    LoadedNoiseResult

Result of `load_scan` for a noise characterization file
(`scan_type = "noise"`). Carries the per-time-constant noise samples and
the Allan deviation arrays. All fields are already plain data.
"""
struct LoadedNoiseResult
    time_constants::Vector{Float64}
    noise_rms::Vector{Float64}
    noise_mean::Vector{Float64}
    samples::Vector{Float64}
    statistics::Dict{String,Float64}
    allan_taus::Vector{Float64}
    allan_devs::Vector{Float64}
    timestamp::DateTime
    duration_seconds::Float64
    instrument_state::Dict{String,Any}
    scan_params::Dict{String,Any}
    description::String
    comment::String
end

"""
    LoadedCompositeResult

Result of `load_scan` for a composite scan file (`scan_type = "composite"`).
A composite scan is N spectra (each at a different fixed delay) plus M
kinetic traces (each at a different fixed wavelength), sharing one root
description, comment, and instrument_state. Either group may be empty.
"""
struct LoadedCompositeResult
    spectra::Vector{LoadedSpectralResult}
    traces::Vector{LoadedScanResult}
    timestamp::DateTime
    duration_seconds::Float64
    instrument_state::Dict{String,Any}
    scan_params::Dict{String,Any}
    description::String
    comment::String
end
