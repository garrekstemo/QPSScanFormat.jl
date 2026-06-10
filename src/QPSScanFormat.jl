module QPSScanFormat

using Dates
using HDF5
using Statistics

include("schema.jl")
include("types.jl")
include("helpers.jl")
include("write.jl")
include("read.jl")
include("rewrite.jl")

# Schema
export FORMAT_VERSION, FORMAT_TAG
export SCAN_TYPES
export SCAN_TYPE_KINETIC, SCAN_TYPE_SPECTRUM, SCAN_TYPE_COMPOSITE,
       SCAN_TYPE_BROADBAND, SCAN_TYPE_NOISE
export is_hdf5_path

# Loaded result types
export LoadedScanResult, LoadedSpectralResult, LoadedCompositeResult, LoadedNoiseResult

# Reader
export load_scan

# Writers (one per scan_type; QPSDrive wraps these with its scan-struct dispatch)
export save_kinetic_scan, save_spectral_scan, save_composite_scan,
       save_broadband_scan, save_noise_scan

# In-place rewrites
export update_scan_description!, update_scan_comment!, update_scan_sample_name!

end # module
