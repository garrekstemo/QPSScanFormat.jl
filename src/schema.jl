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
