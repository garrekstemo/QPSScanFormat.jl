# Loaded result types returned by `load_scan`.
#
# These wrap OpticalSpectroscopy data types with scan-output metadata that
# `LoadedNoiseResult`. We can't reconstruct live instrument refs from a
# file, so instrument_state and scan_params are held as Dicts.

"""
    LoadedScanResult

Result of `load_scan` for a kinetic scan file (`scan_type = "kinetic"`).

# Fields
- `trace::TATrace` — mean X signal over time
- `sweeps::Union{SweepData,Nothing}` — per-sweep raw X/Y/DC (nothing for legacy files)
- `timestamp::DateTime` — when the scan started
- `duration_seconds::Float64` — elapsed wall time
- `instrument_state::Dict{String,Any}` — snapshots of each instrument at scan start
- `scan_params::Dict{String,Any}` — averages, settle_time, accumulations, metadata
- `description::String` — short human-readable scan description
- `comment::String` — long free-form comment
"""
struct LoadedScanResult
    trace::TATrace
    sweeps::Union{SweepData, Nothing}
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
"""
struct LoadedSpectralResult
    spectrum::TASpectrum
    sweeps::Union{SweepData, Nothing}
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
the Allan deviation arrays.
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
