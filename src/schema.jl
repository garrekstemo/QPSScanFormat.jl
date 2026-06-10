# Schema constants for the QPSDrive HDF5 scan format.
#
# The on-disk format is "QPSDrive/<major>.<minor>" stamped as the root
# `format` attribute. Reader behavior is driven off the `scan_type` attribute.

const FORMAT_VERSION = v"1.0"
const FORMAT_TAG = "QPSDrive/$(FORMAT_VERSION.major).$(FORMAT_VERSION.minor)"

# Root attribute keys
const ATTR_FORMAT = "format"
const ATTR_SCAN_TYPE = "scan_type"
const ATTR_TIMESTAMP = "timestamp"
const ATTR_DESCRIPTION = "description"
const ATTR_COMMENT = "comment"
const ATTR_DURATION = "duration_seconds"

# Recognized scan_type values. Legacy "spectral" maps to "spectrum" on read.
const SCAN_TYPE_KINETIC = "kinetic"
const SCAN_TYPE_SPECTRUM = "spectrum"
const SCAN_TYPE_SPECTRAL_LEGACY = "spectral"
const SCAN_TYPE_COMPOSITE = "composite"
const SCAN_TYPE_BROADBAND = "broadband"
const SCAN_TYPE_NOISE = "noise"

const SCAN_TYPES = (
    SCAN_TYPE_KINETIC,
    SCAN_TYPE_SPECTRUM,
    SCAN_TYPE_COMPOSITE,
    SCAN_TYPE_BROADBAND,
    SCAN_TYPE_NOISE,
)

"""
    is_hdf5_path(path) -> Bool

Whether `path` looks like an HDF5 scan file by extension (`.h5` or `.hdf5`).
"""
is_hdf5_path(path::AbstractString) = endswith(path, ".h5") || endswith(path, ".hdf5")

# ─── Format version validation ──────────────────────────────────────────────

# Parse a root `format` attribute ("QPSDrive/<major>.<minor>") into a
# VersionNumber, or nothing if the tag is not in that shape.
function _parse_format_tag(tag::AbstractString)
    m = match(r"^QPSDrive/(\d+)\.(\d+)$", tag)
    m === nothing && return nothing
    VersionNumber(parse(Int, m.captures[1]), parse(Int, m.captures[2]))
end

# Semver-style compatibility check of a file's root `format` attribute
# against FORMAT_VERSION. Policy:
# - missing attribute        -> error (not a QPSDrive scan file)
# - unparseable tag          -> error (unknown producer)
# - file major > supported   -> error (incompatible; reader must be upgraded)
# - file minor > supported   -> warn and proceed (minor bumps are additive)
# - otherwise                -> silent pass
function _check_format_version(fid, path::AbstractString)
    a = attributes(fid)
    haskey(a, ATTR_FORMAT) || error(
        "load_scan: '$path' has no 'format' attribute — not a QPSDrive scan file " *
        "(this reader supports $FORMAT_TAG)")
    tag = read(a[ATTR_FORMAT])
    v = _parse_format_tag(tag)
    v === nothing && error(
        "load_scan: '$path' has unrecognized format tag \"$tag\" " *
        "(this reader supports $FORMAT_TAG)")
    if v.major > FORMAT_VERSION.major
        error("load_scan: '$path' is format QPSDrive/$(v.major).$(v.minor), " *
              "which is newer than the supported $FORMAT_TAG — " *
              "upgrade QPSScanFormat to read this file")
    elseif v.major == FORMAT_VERSION.major && v.minor > FORMAT_VERSION.minor
        @warn "load_scan: file format QPSDrive/$(v.major).$(v.minor) is newer than " *
              "supported $FORMAT_TAG; fields unknown to this reader will be ignored" path
    end
    return v
end
