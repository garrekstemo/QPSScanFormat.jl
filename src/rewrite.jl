# In-place attribute rewrites for already-saved files.
#
# Used by the QPSConsole rename / re-comment / sample-tag flows so the display
# fields in the GUI survive a restart. Each rewrite opens the file in r+ mode,
# deletes the existing attribute (if any), and writes the new value.

"""
    update_scan_description!(path, description; sub_path=nothing)

Rewrite the `description` attribute. With `sub_path` nothing/empty the root
attribute is replaced (single scans, composite top-level). With a sub-group
path (e.g. `"data/spectra/spectrum_001"`) that child's `description` is
replaced instead.
"""
function update_scan_description!(path::AbstractString, description::AbstractString;
                                   sub_path::Union{AbstractString,Nothing}=nothing)
    _update_scalar_attr!(path, ATTR_DESCRIPTION, description; sub_path=sub_path)
end

"""
    update_scan_comment!(path, comment; sub_path=nothing)

Rewrite the `comment` attribute. Mirrors `update_scan_description!`.
"""
function update_scan_comment!(path::AbstractString, comment::AbstractString;
                               sub_path::Union{AbstractString,Nothing}=nothing)
    _update_scalar_attr!(path, ATTR_COMMENT, comment; sub_path=sub_path)
end

"""
    update_scan_sample_name!(path, sample_name)

Rewrite the `sample_name` attribute inside the file's `scan/metadata`
group. Unlike `update_scan_description!` / `update_scan_comment!` (which
target root or sub-group attributes), `sample_name` is per-file — composite
scans share one sample across all sub-scans. Creates `scan/metadata` if the
file pre-dates that group. Empty string is a valid value and clears the
attribute.
"""
function update_scan_sample_name!(path::AbstractString, sample_name::AbstractString)
    isfile(path) || error("File not found: $path")
    h5open(String(path), "r+") do fid
        mg = if haskey(fid, "scan/metadata")
            fid["scan/metadata"]
        elseif haskey(fid, "scan")
            create_group(fid["scan"], "metadata")
        else
            g = create_group(fid, "scan")
            create_group(g, "metadata")
        end
        a = attributes(mg)
        if haskey(a, "sample_name")
            delete_attribute(mg, "sample_name")
        end
        a["sample_name"] = String(sample_name)
    end
    return nothing
end

# Shared body for update_scan_description! / update_scan_comment!.
function _update_scalar_attr!(path::AbstractString, key::AbstractString,
                              value::AbstractString;
                              sub_path::Union{AbstractString,Nothing}=nothing)
    isfile(path) || error("File not found: $path")
    h5open(String(path), "r+") do fid
        parent = sub_path === nothing || isempty(sub_path) ? fid : fid[String(sub_path)]
        a = attributes(parent)
        if haskey(a, key)
            delete_attribute(parent, key)
        end
        a[key] = String(value)
    end
    return nothing
end
