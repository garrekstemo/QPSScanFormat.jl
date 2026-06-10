# Internal helpers: attribute marshalling, instrument state, sweep data, unit conversions.
#
# These exist as duplicated implementations in QPSDrive's runtime (used during
# scans before any file is written). Keeping them internal here means
# QPSScanFormat has no QPSDrive dependency.

# ─── Wavelength ⇄ wavenumber ────────────────────────────────────────────────

wl_to_wn(wavelength_nm) = 1e7 / wavelength_nm
wn_to_wl(wavenumber_cm) = 1e7 / wavenumber_cm

# ─── NaN-safe statistics for sweep matrices ─────────────────────────────────

# Mean across columns (sweeps) at each row (point), ignoring NaN.
function _nanmean(m::AbstractMatrix{<:Real})
    n = size(m, 1)
    result = zeros(n)
    for i in 1:n
        vals = filter(!isnan, @view m[i, :])
        result[i] = isempty(vals) ? NaN : mean(vals)
    end
    return result
end

# Std across columns at each row, ignoring NaN. Returns 0.0 for rows with <2 finite values.
function _nanstd(m::AbstractMatrix{<:Real})
    n = size(m, 1)
    result = zeros(n)
    for i in 1:n
        vals = filter(!isnan, @view m[i, :])
        result[i] = length(vals) < 2 ? 0.0 : std(vals; corrected=true)
    end
    return result
end

# ─── HDF5 attribute marshalling ─────────────────────────────────────────────

# Write a single attribute, converting unsupported types to strings.
# `nothing` writes nothing — the absence of the attribute on read is the
# correct in-band signal for "this field was unset." Otherwise we'd persist
# the literal string "nothing", which round-trips incorrectly on every typed reader.
function _write_attr!(parent, key::String, val)
    val === nothing && return
    if val isa AbstractString
        attributes(parent)[key] = String(val)
    elseif val isa Bool
        attributes(parent)[key] = Int(val)  # HDF5 stores bools as int
    elseif val isa Integer
        attributes(parent)[key] = Int(val)
    elseif val isa AbstractFloat
        attributes(parent)[key] = Float64(val)
    else
        attributes(parent)[key] = string(val)
    end
end

# ─── Instrument state group (write + read) ──────────────────────────────────

function _write_instrument_state!(parent, state::Dict{String,Any})
    g = create_group(parent, "instrument_state")
    for (name, inst_dict) in state
        ig = create_group(g, name)
        for (k, v) in inst_dict
            _write_attr!(ig, k, v)
        end
    end
end

function _read_instrument_state(fid)
    state = Dict{String,Any}()
    haskey(fid, "instrument_state") || return state
    g = fid["instrument_state"]
    for name in keys(g)
        ig = g[name]
        inst = Dict{String,Any}()
        for attr_name in keys(attributes(ig))
            inst[attr_name] = read(attributes(ig)[attr_name])
        end
        state[name] = inst
    end
    return state
end

# ─── Scan params group (write + read) ───────────────────────────────────────

# Write `scan/` group attributes from a flat dict. Reserved key "metadata"
# (a nested Dict) becomes a `scan/metadata` sub-group.
function _write_scan_params!(parent, params::Dict{String,Any})
    g = create_group(parent, "scan")
    for (k, v) in params
        k == "metadata" && continue
        _write_attr!(g, string(k), v)
    end
    meta = get(params, "metadata", nothing)
    if meta isa AbstractDict && !isempty(meta)
        mg = create_group(g, "metadata")
        for (k, v) in meta
            _write_attr!(mg, string(k), v)
        end
    end
end

function _read_scan_params(fid)
    params = Dict{String,Any}()
    haskey(fid, "scan") || return params
    g = fid["scan"]
    for attr_name in keys(attributes(g))
        params[attr_name] = read(attributes(g)[attr_name])
    end
    if haskey(g, "metadata")
        mg = g["metadata"]
        meta = Dict{String,Any}()
        for attr_name in keys(attributes(mg))
            meta[attr_name] = read(attributes(mg)[attr_name])
        end
        params["metadata"] = meta
    end
    return params
end

# ─── Per-sweep raw data (write + read) ──────────────────────────────────────

# Write per-sweep multi-channel data + computed statistics under `data/`.
# Duck-typed: accepts anything with X/Y/DC matrix fields (the reader's
# (X, Y, DC) NamedTuple, OpticalSpectroscopy.SweepData from QPSDrive, ...).
function _write_sweep_data!(dg, sweeps)
    n_sweeps = size(sweeps.X, 2)

    sg = create_group(dg, "sweeps")
    for j in 1:n_sweeps
        label = lpad(j, 3, '0')
        sweep_g = create_group(sg, label)
        sweep_g["X"] = collect(Float64, sweeps.X[:, j])
        sweep_g["Y"] = collect(Float64, sweeps.Y[:, j])
        sweep_g["DC"] = collect(Float64, sweeps.DC[:, j])
    end

    dg["X_mean"] = _nanmean(sweeps.X)
    dg["X_std"] = _nanstd(sweeps.X)
    dg["Y_mean"] = _nanmean(sweeps.Y)
    dg["DC_mean"] = _nanmean(sweeps.DC)
end

# Read per-sweep data from `data/sweeps/`. Returns an (X, Y, DC)
# NamedTuple of Matrix{Float64}, or nothing if the group is absent
# (legacy file without per-sweep data).
function _read_sweep_data(dg)
    haskey(dg, "sweeps") || return nothing
    sg = dg["sweeps"]
    sweep_names = sort(collect(keys(sg)))
    isempty(sweep_names) && return nothing

    first_g = sg[sweep_names[1]]
    n = length(read(first_g["X"]))
    n_sweeps = length(sweep_names)

    X = Matrix{Float64}(undef, n, n_sweeps)
    Y = Matrix{Float64}(undef, n, n_sweeps)
    DC = Matrix{Float64}(undef, n, n_sweeps)

    for (j, name) in enumerate(sweep_names)
        sweep_g = sg[name]
        X[:, j] = read(sweep_g["X"])
        Y[:, j] = read(sweep_g["Y"])
        DC[:, j] = read(sweep_g["DC"])
    end

    return SweepArrays((X, Y, DC))
end

# Pick the mean signal for a `data/` group, preferring `X_mean` if available,
# falling back to per-sweep average, then legacy `signal` dataset, then bare `X_mean`.
function _read_mean_signal(dg, sweeps::Union{SweepArrays,Nothing})
    if sweeps !== nothing
        return haskey(dg, "X_mean") ? read(dg["X_mean"]) : _nanmean(sweeps.X)
    elseif haskey(dg, "signal")
        return read(dg["signal"])
    else
        return read(dg["X_mean"])
    end
end
