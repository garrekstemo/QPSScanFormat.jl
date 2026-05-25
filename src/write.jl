# save_scan dispatch by underlying data type.
#
# QPSDrive translates its scan-struct vocabulary (KineticScan, SpectralScan,
# CompositeScan, NoiseScan) into the dict-based `scan_params` interface
# below at the call site, so QPSScanFormat stays free of QPSDrive's types.

"""
    save_kinetic_scan(trace, path; kwargs...)

Save a kinetic scan: a `TATrace` (mean signal vs delay) plus optional
per-sweep raw data, instrument state, and scan parameters.

# Keyword arguments
- `sweeps::Union{SweepData,Nothing}` — per-sweep X/Y/DC matrices
- `scan_params::Dict{String,Any}` — averages, settle_time_s, accumulations, metadata
- `instrument_state::Dict{String,Any}` — per-instrument snapshot dicts
- `description::AbstractString` — short scan label
- `comment::AbstractString` — free-form comment (empty by default)
- `timestamp::DateTime` — scan start (defaults to `now()`)
- `duration_seconds::Real` — elapsed wall time
"""
function save_kinetic_scan(trace::TATrace, path::AbstractString;
                           sweeps::Union{SweepData,Nothing} = nothing,
                           scan_params::Dict{String,Any} = Dict{String,Any}(),
                           instrument_state::Dict{String,Any} = Dict{String,Any}(),
                           description::AbstractString = "",
                           comment::AbstractString = "",
                           timestamp::DateTime = now(),
                           duration_seconds::Real = 0.0)
    is_hdf5_path(path) || error("save_kinetic_scan: path must be .h5 or .hdf5; got $path")
    tmp = path * ".tmp"
    h5open(tmp, "w") do fid
        _write_root_attrs!(fid, SCAN_TYPE_KINETIC, timestamp, description, comment, duration_seconds)
        _write_instrument_state!(fid, instrument_state)
        _write_scan_params!(fid, scan_params)
        dg = create_group(fid, "data")
        dg["time_ps"] = trace.time
        if sweeps === nothing
            # No per-sweep data; persist the mean signal so the reader has
            # something to deliver. The trace's signal IS the mean already.
            dg["X_mean"] = collect(Float64, trace.signal)
        else
            _write_sweep_data!(dg, sweeps)
        end
    end
    mv(tmp, path; force=true)
    return path
end

"""
    save_spectral_scan(spectrum, wavelengths_nm, path; kwargs...)

Save a spectral scan: a `TASpectrum` (signal vs wavenumber) plus its
companion `wavelengths_nm` axis, optional per-sweep raw data, and metadata.
The on-disk canonical axis is wavelength_nm; the wavenumber axis is
derived from it on read.
"""
function save_spectral_scan(spectrum::TASpectrum, wavelengths_nm::AbstractVector{<:Real},
                            path::AbstractString;
                            sweeps::Union{SweepData,Nothing} = nothing,
                            scan_params::Dict{String,Any} = Dict{String,Any}(),
                            instrument_state::Dict{String,Any} = Dict{String,Any}(),
                            description::AbstractString = "",
                            comment::AbstractString = "",
                            timestamp::DateTime = now(),
                            duration_seconds::Real = 0.0)
    is_hdf5_path(path) || error("save_spectral_scan: path must be .h5 or .hdf5; got $path")
    tmp = path * ".tmp"
    h5open(tmp, "w") do fid
        _write_root_attrs!(fid, SCAN_TYPE_SPECTRUM, timestamp, description, comment, duration_seconds)
        _write_instrument_state!(fid, instrument_state)
        _write_scan_params!(fid, scan_params)
        dg = create_group(fid, "data")
        dg["wavelength_nm"] = collect(Float64, wavelengths_nm)
        if sweeps === nothing
            dg["X_mean"] = collect(Float64, spectrum.signal)
        else
            _write_sweep_data!(dg, sweeps)
        end
    end
    mv(tmp, path; force=true)
    return path
end

"""
    save_broadband_scan(matrix, path; kwargs...)

Save a broadband TA matrix (`TAMatrix`, time × wavelength_nm).
"""
function save_broadband_scan(matrix::TAMatrix, path::AbstractString;
                             instrument_state::Dict{String,Any} = Dict{String,Any}(),
                             metadata::Dict{String,Any} = Dict{String,Any}(),
                             description::AbstractString = "",
                             comment::AbstractString = "",
                             timestamp::DateTime = now(),
                             duration_seconds::Real = 0.0)
    is_hdf5_path(path) || error("save_broadband_scan: path must be .h5 or .hdf5; got $path")
    tmp = path * ".tmp"
    h5open(tmp, "w") do fid
        _write_root_attrs!(fid, SCAN_TYPE_BROADBAND, timestamp, description, comment, duration_seconds)
        isempty(instrument_state) || _write_instrument_state!(fid, instrument_state)
        if !isempty(metadata)
            mg = create_group(fid, "scan/metadata")
            for (k, v) in metadata
                _write_attr!(mg, string(k), v)
            end
        end
        g = create_group(fid, "data")
        g["time_ps"] = matrix.time
        g["wavelength_nm"] = matrix.wavelength
        g["signal"] = matrix.data
    end
    mv(tmp, path; force=true)
    return path
end

"""
    save_noise_scan(path; kwargs...)

Save a noise characterization result. Takes the raw vectors and statistics
dict directly — there's no SpectroscopyTools type for this since it's
not a spectroscopy product.

# Keyword arguments
- `time_constants::Vector{Float64}`
- `noise_rms::Vector{Float64}`
- `noise_mean::Vector{Float64}`
- `samples::Vector{Float64}`
- `allan_taus::Vector{Float64}`
- `allan_devs::Vector{Float64}`
- `statistics::Dict{String,Float64}` — optional summary stats
"""
function save_noise_scan(path::AbstractString;
                         time_constants::AbstractVector{<:Real},
                         noise_rms::AbstractVector{<:Real},
                         noise_mean::AbstractVector{<:Real},
                         samples::AbstractVector{<:Real},
                         allan_taus::AbstractVector{<:Real},
                         allan_devs::AbstractVector{<:Real},
                         statistics::Dict{String,Float64} = Dict{String,Float64}(),
                         scan_params::Dict{String,Any} = Dict{String,Any}(),
                         instrument_state::Dict{String,Any} = Dict{String,Any}(),
                         description::AbstractString = "",
                         comment::AbstractString = "",
                         timestamp::DateTime = now(),
                         duration_seconds::Real = 0.0)
    is_hdf5_path(path) || error("save_noise_scan: path must be .h5 or .hdf5; got $path")
    tmp = path * ".tmp"
    h5open(tmp, "w") do fid
        _write_root_attrs!(fid, SCAN_TYPE_NOISE, timestamp, description, comment, duration_seconds)
        _write_instrument_state!(fid, instrument_state)
        _write_scan_params!(fid, scan_params)
        g = create_group(fid, "data")
        g["time_constants"] = collect(Float64, time_constants)
        g["noise_rms"] = collect(Float64, noise_rms)
        g["noise_mean"] = collect(Float64, noise_mean)
        g["samples"] = collect(Float64, samples)
        g["allan_taus"] = collect(Float64, allan_taus)
        g["allan_devs"] = collect(Float64, allan_devs)
        if !isempty(statistics)
            sg = create_group(g, "statistics")
            for (k, v) in statistics
                attributes(sg)[k] = Float64(v)
            end
        end
    end
    mv(tmp, path; force=true)
    return path
end

"""
    save_composite_scan(path; spectra, kinetics, kwargs...)

Save a composite scan: N spectra and M kinetic traces sharing one root
description/comment/instrument_state.

`spectra` is a vector of NamedTuples with required fields
`(spectrum::TASpectrum, wavelengths::Vector{Float64}, sweeps::Union{SweepData,Nothing},
description::String, comment::String, timestamp::DateTime, duration_seconds::Float64)`
and optional `delay_ps::Float64`.

`kinetics` is a vector of NamedTuples with required fields
`(trace::TATrace, sweeps::Union{SweepData,Nothing}, description::String,
comment::String, timestamp::DateTime, duration_seconds::Float64)`
and optional `wavelength_nm::Float64`.
"""
function save_composite_scan(path::AbstractString;
                             spectra::AbstractVector = (),
                             kinetics::AbstractVector = (),
                             scan_params::Dict{String,Any} = Dict{String,Any}(),
                             instrument_state::Dict{String,Any} = Dict{String,Any}(),
                             description::AbstractString = "",
                             comment::AbstractString = "",
                             timestamp::DateTime = now(),
                             duration_seconds::Real = 0.0)
    is_hdf5_path(path) || error("save_composite_scan: path must be .h5 or .hdf5; got $path")
    tmp = path * ".tmp"
    h5open(tmp, "w") do fid
        _write_root_attrs!(fid, SCAN_TYPE_COMPOSITE, timestamp, description, comment, duration_seconds)
        _write_instrument_state!(fid, instrument_state)
        _write_scan_params!(fid, scan_params)

        if !isempty(spectra)
            sg = create_group(fid, "data/spectra")
            for (i, sp) in enumerate(spectra)
                label = "spectrum_$(lpad(i, 3, '0'))"
                g = create_group(sg, label)
                g["wavelength_nm"] = collect(Float64, sp.wavelengths)
                g["wavenumber_cm"] = collect(Float64, sp.spectrum.wavenumber)
                g["signal"] = collect(Float64, sp.spectrum.signal)
                sp.sweeps === nothing || _write_sweep_data!(g, sp.sweeps)
                attributes(g)[ATTR_DESCRIPTION] = String(sp.description)
                attributes(g)[ATTR_COMMENT] = String(sp.comment)
                attributes(g)[ATTR_TIMESTAMP] = string(sp.timestamp)
                attributes(g)[ATTR_DURATION] = Float64(sp.duration_seconds)
                delay = get(sp, :delay_ps, nothing)
                delay === nothing || (attributes(g)["delay_ps"] = Float64(delay))
            end
        end

        if !isempty(kinetics)
            kg = create_group(fid, "data/kinetics")
            for (j, tr) in enumerate(kinetics)
                label = "trace_$(lpad(j, 3, '0'))"
                tg = create_group(kg, label)
                tg["time_ps"] = collect(Float64, tr.trace.time)
                tr.sweeps === nothing || _write_sweep_data!(tg, tr.sweeps)
                attributes(tg)[ATTR_DESCRIPTION] = String(tr.description)
                attributes(tg)[ATTR_COMMENT] = String(tr.comment)
                attributes(tg)[ATTR_TIMESTAMP] = string(tr.timestamp)
                attributes(tg)[ATTR_DURATION] = Float64(tr.duration_seconds)
                wl = get(tr, :wavelength_nm, nothing)
                wl === nothing || (attributes(tg)["wavelength_nm"] = Float64(wl))
            end
        end
    end
    mv(tmp, path; force=true)
    return path
end

# Write the canonical root-attribute set common to every scan_type.
function _write_root_attrs!(fid, scan_type::AbstractString,
                            timestamp::DateTime,
                            description::AbstractString,
                            comment::AbstractString,
                            duration_seconds::Real)
    attrs = attributes(fid)
    attrs[ATTR_FORMAT] = FORMAT_TAG
    attrs[ATTR_SCAN_TYPE] = String(scan_type)
    attrs[ATTR_TIMESTAMP] = string(timestamp)
    attrs[ATTR_DESCRIPTION] = String(description)
    attrs[ATTR_COMMENT] = String(comment)
    attrs[ATTR_DURATION] = Float64(duration_seconds)
end
