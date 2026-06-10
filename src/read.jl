# load_scan + per-scan_type dispatch.
#
# Returns one of the Loaded* types from types.jl. Legacy compatibility:
# - `scan_type == "spectral"` reads as spectrum
# - missing `comment` attribute reads as ""
# - missing `X_mean` falls back to legacy `signal` dataset, then to NaN-mean of sweeps

"""
    load_scan(path) -> Loaded* result

Load a QPSDrive HDF5 scan file. Returns the appropriate Loaded type
based on the `scan_type` root attribute.
"""
function load_scan(path::AbstractString)
    h5open(String(path), "r") do fid
        _check_format_version(fid, path)
        scan_type = read(attributes(fid)[ATTR_SCAN_TYPE])
        if scan_type == SCAN_TYPE_KINETIC
            return _load_kinetic(fid)
        elseif scan_type == SCAN_TYPE_SPECTRUM || scan_type == SCAN_TYPE_SPECTRAL_LEGACY
            return _load_spectral(fid)
        elseif scan_type == SCAN_TYPE_COMPOSITE
            return _load_composite(fid)
        elseif scan_type == SCAN_TYPE_BROADBAND
            return _load_broadband(fid)
        elseif scan_type == SCAN_TYPE_NOISE
            return _load_noise(fid)
        else
            error("Unknown scan_type: $scan_type")
        end
    end
end

# Pull a string attribute, defaulting to "" if absent.
function _read_str_attr(parent, key::String)
    a = attributes(parent)
    haskey(a, key) ? read(a[key]) : ""
end

function _load_kinetic(fid)
    dg = fid["data"]
    time_ps = read(dg["time_ps"])
    sweeps = _read_sweep_data(dg)
    x_mean = _read_mean_signal(dg, sweeps)

    trace = TATrace(time_ps, x_mean)
    LoadedScanResult(
        trace,
        sweeps,
        DateTime(read(attributes(fid)[ATTR_TIMESTAMP])),
        read(attributes(fid)[ATTR_DURATION]),
        _read_instrument_state(fid),
        _read_scan_params(fid),
        _read_str_attr(fid, ATTR_DESCRIPTION),
        _read_str_attr(fid, ATTR_COMMENT),
    )
end

function _load_spectral(fid)
    dg = fid["data"]

    # Canonical axis is wavelength_nm; fall back to wavenumber_cm for legacy files
    if haskey(dg, "wavelength_nm")
        wl = read(dg["wavelength_nm"])
        wn = wl_to_wn.(wl)
    elseif haskey(dg, "wavenumber_cm")
        wn = read(dg["wavenumber_cm"])
        wl = wn_to_wl.(wn)
    else
        error("Spectral scan file missing both wavelength_nm and wavenumber_cm")
    end

    sweeps = _read_sweep_data(dg)
    x_mean = _read_mean_signal(dg, sweeps)

    spectrum = TASpectrum(wn, x_mean)
    LoadedSpectralResult(
        spectrum,
        sweeps,
        wl,
        DateTime(read(attributes(fid)[ATTR_TIMESTAMP])),
        read(attributes(fid)[ATTR_DURATION]),
        _read_instrument_state(fid),
        _read_scan_params(fid),
        _read_str_attr(fid, ATTR_DESCRIPTION),
        _read_str_attr(fid, ATTR_COMMENT),
    )
end

function _load_composite(fid)
    spectra = LoadedSpectralResult[]
    if haskey(fid, "data/spectra")
        sg = fid["data/spectra"]
        for name in sort(collect(keys(sg)))
            g = sg[name]
            wl = read(g["wavelength_nm"])
            wn = haskey(g, "wavenumber_cm") ? read(g["wavenumber_cm"]) : wl_to_wn.(wl)
            sweeps = _read_sweep_data(g)
            x_mean = _read_mean_signal(g, sweeps)

            sp = TASpectrum(wn, x_mean)
            params = Dict{String,Any}()
            if haskey(attributes(g), "delay_ps")
                params["delay_ps"] = read(attributes(g)["delay_ps"])
            end
            # The sub-path is recorded so the rename flow can target this
            # exact group when overwriting description/comment.
            params["sub_path"] = "data/spectra/$name"

            push!(spectra, LoadedSpectralResult(
                sp,
                sweeps,
                wl,
                DateTime(read(attributes(g)[ATTR_TIMESTAMP])),
                read(attributes(g)[ATTR_DURATION]),
                Dict{String,Any}(),
                params,
                _read_str_attr(g, ATTR_DESCRIPTION),
                _read_str_attr(g, ATTR_COMMENT),
            ))
        end
    end

    traces = LoadedScanResult[]
    if haskey(fid, "data/kinetics")
        kg = fid["data/kinetics"]
        for name in sort(collect(keys(kg)))
            tg = kg[name]
            t = read(tg["time_ps"])
            sweeps = _read_sweep_data(tg)
            x_mean = _read_mean_signal(tg, sweeps)

            tr = TATrace(t, x_mean)
            params = Dict{String,Any}()
            if haskey(attributes(tg), "wavelength_nm")
                params["wavelength_nm"] = read(attributes(tg)["wavelength_nm"])
            end
            params["sub_path"] = "data/kinetics/$name"

            push!(traces, LoadedScanResult(
                tr,
                sweeps,
                DateTime(read(attributes(tg)[ATTR_TIMESTAMP])),
                read(attributes(tg)[ATTR_DURATION]),
                Dict{String,Any}(),
                params,
                _read_str_attr(tg, ATTR_DESCRIPTION),
                _read_str_attr(tg, ATTR_COMMENT),
            ))
        end
    end

    LoadedCompositeResult(
        spectra,
        traces,
        DateTime(read(attributes(fid)[ATTR_TIMESTAMP])),
        read(attributes(fid)[ATTR_DURATION]),
        _read_instrument_state(fid),
        _read_scan_params(fid),
        _read_str_attr(fid, ATTR_DESCRIPTION),
        _read_str_attr(fid, ATTR_COMMENT),
    )
end

function _load_broadband(fid)
    time_ps = read(fid["data/time_ps"])
    wavelength_nm = read(fid["data/wavelength_nm"])
    signal = read(fid["data/signal"])
    TAMatrix(time_ps, wavelength_nm, signal)
end

function _load_noise(fid)
    g = fid["data"]
    time_constants = read(g["time_constants"])
    noise_rms = read(g["noise_rms"])
    noise_mean = read(g["noise_mean"])
    samples = read(g["samples"])
    allan_taus = read(g["allan_taus"])
    allan_devs = read(g["allan_devs"])

    statistics = Dict{String,Float64}()
    if haskey(g, "statistics")
        sg = g["statistics"]
        for attr_name in keys(attributes(sg))
            statistics[attr_name] = Float64(read(attributes(sg)[attr_name]))
        end
    end

    LoadedNoiseResult(
        time_constants,
        noise_rms,
        noise_mean,
        samples,
        statistics,
        allan_taus,
        allan_devs,
        DateTime(read(attributes(fid)[ATTR_TIMESTAMP])),
        read(attributes(fid)[ATTR_DURATION]),
        _read_instrument_state(fid),
        _read_scan_params(fid),
        _read_str_attr(fid, ATTR_DESCRIPTION),
        _read_str_attr(fid, ATTR_COMMENT),
    )
end
