using Test
using Aqua
using Dates
using HDF5
using QPSScanFormat

# Helpers for building fixtures. Writers are duck-typed: any object with
# the right fields works (NamedTuples here; OpticalSpectroscopy's
# KineticTrace/Spectrum/TimeResolvedMatrix/SweepData in QPSDrive).
function _mock_trace(npts=10)
    time_ps = collect(range(-1.0, 5.0; length=npts))
    signal = sin.(time_ps)
    (time = time_ps, signal = signal)
end

function _mock_spectrum(npts=8)
    wl = collect(range(2000.0, 2200.0; length=npts))  # nm
    wn = QPSScanFormat.wl_to_wn.(wl)
    signal = randn(npts)
    (wavenumber = wn, signal = signal), wl
end

function _mock_sweeps(n_points=10, n_sweeps=3)
    X = randn(n_points, n_sweeps)
    Y = randn(n_points, n_sweeps)
    DC = ones(n_points, n_sweeps)
    (X = X, Y = Y, DC = DC)
end

@testset "QPSScanFormat" begin

    @testset "Aqua quality assurance" begin
        Aqua.test_all(QPSScanFormat)
    end

    @testset "schema constants" begin
        @test QPSScanFormat.FORMAT_TAG == "QPSDrive/1.0"
        @test QPSScanFormat.SCAN_TYPE_KINETIC == "kinetic"
        @test QPSScanFormat.SCAN_TYPE_SPECTRUM == "spectrum"
        @test is_hdf5_path("foo.h5")
        @test is_hdf5_path("foo.hdf5")
        @test !is_hdf5_path("foo.csv")
    end

    @testset "kinetic round-trip" begin
        trace = _mock_trace(20)
        sweeps = _mock_sweeps(20, 4)

        mktempdir() do dir
            path = joinpath(dir, "kinetic.h5")
            save_kinetic_scan(trace, path;
                sweeps = sweeps,
                scan_params = Dict{String,Any}(
                    "averages" => 100,
                    "settle_time_s" => 0.1,
                    "accumulations" => 1,
                    "metadata" => Dict{String,Any}("sample_name" => "W(CO)6"),
                ),
                instrument_state = Dict{String,Any}(
                    "stage" => Dict{String,Any}("position_ps" => 0.5),
                ),
                description = "test kinetic",
                comment = "first sweep looked clean",
                duration_seconds = 42.5,
            )

            r = load_scan(path)
            @test r isa LoadedScanResult
            @test r.description == "test kinetic"
            @test r.comment == "first sweep looked clean"
            @test r.duration_seconds ≈ 42.5
            # Plain-data contract: trace is a (time, signal) NamedTuple of
            # Float64 vectors — no analysis types in the format layer.
            @test r.trace isa NamedTuple{(:time, :signal)}
            @test r.trace.time isa Vector{Float64}
            @test r.trace.signal isa Vector{Float64}
            @test r.trace.time ≈ trace.time
            # Plain-data contract: sweeps is an (X, Y, DC) NamedTuple of matrices.
            @test r.sweeps isa NamedTuple{(:X, :Y, :DC)}
            @test r.sweeps.X isa Matrix{Float64}
            @test size(r.sweeps.X) == size(sweeps.X)
            @test r.sweeps.X ≈ sweeps.X
            @test r.scan_params["averages"] == 100
            @test r.scan_params["metadata"]["sample_name"] == "W(CO)6"
            @test r.instrument_state["stage"]["position_ps"] ≈ 0.5
        end
    end

    @testset "spectral round-trip (canonical wavelength)" begin
        spec, wl = _mock_spectrum(12)
        sweeps = _mock_sweeps(12, 2)

        mktempdir() do dir
            path = joinpath(dir, "spectrum.h5")
            save_spectral_scan(spec, wl, path;
                sweeps = sweeps,
                scan_params = Dict{String,Any}("averages" => 50, "delay_ps" => 1.5),
                description = "test spectrum",
                comment = "",
                duration_seconds = 12.0,
            )

            r = load_scan(path)
            @test r isa LoadedSpectralResult
            @test r.wavelengths ≈ wl
            # Plain-data contract: spectrum is a (wavenumber, signal) NamedTuple.
            @test r.spectrum isa NamedTuple{(:wavenumber, :signal)}
            @test r.spectrum.wavenumber isa Vector{Float64}
            @test r.spectrum.signal isa Vector{Float64}
            @test r.spectrum.wavenumber ≈ QPSScanFormat.wl_to_wn.(wl)
            @test r.description == "test spectrum"
            @test r.sweeps isa NamedTuple{(:X, :Y, :DC)}
            @test r.scan_params["delay_ps"] ≈ 1.5
        end
    end

    @testset "broadband round-trip" begin
        time_ps = collect(range(-2.0, 10.0; length=5))
        wl_nm = collect(range(1900.0, 2100.0; length=4))
        data = randn(5, 4)
        mat = (time = time_ps, wavelength = wl_nm, data = data)

        mktempdir() do dir
            path = joinpath(dir, "broadband.h5")
            save_broadband_scan(mat, path;
                description = "test broadband",
                metadata = Dict{String,Any}("sample_name" => "MoS2"),
            )

            r = load_scan(path)
            # Plain-data contract: broadband loads as a (time, wavelength, data)
            # NamedTuple (formerly a bare OpticalSpectroscopy.TAMatrix).
            @test r isa NamedTuple{(:time, :wavelength, :data)}
            @test r.time ≈ time_ps
            @test r.wavelength ≈ wl_nm
            @test r.data isa Matrix{Float64}
            @test r.data ≈ data
        end
    end

    @testset "noise round-trip" begin
        tc = [0.001, 0.01, 0.1]
        rms = [1e-6, 1e-7, 5e-8]
        mean_vec = [1e-3, 1e-3, 1e-3]
        samples = [1000.0, 1000.0, 1000.0]
        allan_taus = [0.01, 0.1, 1.0]
        allan_devs = [2e-7, 5e-8, 1e-8]
        stats = Dict{String,Float64}("best_tc" => 0.01, "min_rms" => 1e-7)

        mktempdir() do dir
            path = joinpath(dir, "noise.h5")
            save_noise_scan(path;
                time_constants = tc,
                noise_rms = rms,
                noise_mean = mean_vec,
                samples = samples,
                allan_taus = allan_taus,
                allan_devs = allan_devs,
                statistics = stats,
                description = "noise floor",
                comment = "post-realignment",
                duration_seconds = 30.0,
            )

            r = load_scan(path)
            @test r isa LoadedNoiseResult
            @test r.time_constants ≈ tc
            @test r.noise_rms ≈ rms
            @test r.allan_devs ≈ allan_devs
            @test r.statistics["best_tc"] ≈ 0.01
            @test r.description == "noise floor"
            @test r.comment == "post-realignment"
        end
    end

    @testset "composite round-trip" begin
        spec1, wl1 = _mock_spectrum(6)
        spec2, wl2 = _mock_spectrum(6)
        trace1 = _mock_trace(8)
        sweeps_s = _mock_sweeps(6, 2)
        sweeps_t = _mock_sweeps(8, 2)
        ts = now()

        mktempdir() do dir
            path = joinpath(dir, "composite.h5")
            save_composite_scan(path;
                spectra = [
                    (spectrum=spec1, wavelengths=wl1, sweeps=sweeps_s,
                     description="early", comment="", timestamp=ts,
                     duration_seconds=10.0, delay_ps=0.5),
                    (spectrum=spec2, wavelengths=wl2, sweeps=sweeps_s,
                     description="late", comment="", timestamp=ts,
                     duration_seconds=10.0, delay_ps=5.0),
                ],
                kinetics = [
                    (trace=trace1, sweeps=sweeps_t,
                     description="@2050nm", comment="", timestamp=ts,
                     duration_seconds=15.0, wavelength_nm=2050.0),
                ],
                description = "kinetics + spectra",
                comment = "good run",
                duration_seconds = 100.0,
            )

            r = load_scan(path)
            @test r isa LoadedCompositeResult
            @test length(r.spectra) == 2
            @test length(r.traces) == 1
            @test r.spectra[1].spectrum isa NamedTuple{(:wavenumber, :signal)}
            @test r.traces[1].trace isa NamedTuple{(:time, :signal)}
            @test r.spectra[1].scan_params["delay_ps"] ≈ 0.5
            @test r.spectra[2].scan_params["delay_ps"] ≈ 5.0
            @test r.spectra[1].scan_params["sub_path"] == "data/spectra/spectrum_001"
            @test r.traces[1].scan_params["wavelength_nm"] ≈ 2050.0
            @test r.traces[1].scan_params["sub_path"] == "data/kinetics/trace_001"
            @test r.description == "kinetics + spectra"
            @test r.spectra[1].description == "early"
        end
    end

    @testset "composite kinetics without sweeps round-trip" begin
        trace = _mock_trace(8)
        ts = now()

        mktempdir() do dir
            path = joinpath(dir, "composite_nosweeps.h5")
            save_composite_scan(path;
                spectra = NamedTuple[],
                kinetics = [
                    (trace=trace, sweeps=nothing,
                     description="no sweeps", comment="", timestamp=ts,
                     duration_seconds=5.0, wavelength_nm=2100.0),
                ],
                description = "kinetics only, no sweeps",
            )

            r = load_scan(path)
            @test r isa LoadedCompositeResult
            @test length(r.traces) == 1
            @test r.traces[1].trace.time ≈ trace.time
            @test r.traces[1].trace.signal ≈ trace.signal
        end
    end

    @testset "composite with only one sub-scan kind" begin
        ts = now()

        mktempdir() do dir
            # Only kinetics (spectra kwarg omitted)
            trace = _mock_trace(6)
            kpath = joinpath(dir, "kinetics_only.h5")
            save_composite_scan(kpath;
                kinetics = [
                    (trace=trace, sweeps=_mock_sweeps(6, 2),
                     description="k only", comment="", timestamp=ts,
                     duration_seconds=1.0),
                ])
            rk = load_scan(kpath)
            @test rk isa LoadedCompositeResult
            @test length(rk.traces) == 1
            @test isempty(rk.spectra)

            # Only spectra (kinetics kwarg omitted)
            spec, wl = _mock_spectrum(6)
            spath = joinpath(dir, "spectra_only.h5")
            save_composite_scan(spath;
                spectra = [
                    (spectrum=spec, wavelengths=wl, sweeps=nothing,
                     description="s only", comment="", timestamp=ts,
                     duration_seconds=1.0),
                ])
            rs = load_scan(spath)
            @test rs isa LoadedCompositeResult
            @test length(rs.spectra) == 1
            @test isempty(rs.traces)

            # Both empty is a clear error, not a useless file
            err = try
                save_composite_scan(joinpath(dir, "empty.h5"))
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("spectra", err.msg) && occursin("kinetics", err.msg)
        end
    end

    @testset "legacy scan_type='spectral' reads as spectrum" begin
        # Hand-build a file with the legacy attribute value
        spec, wl = _mock_spectrum(5)
        mktempdir() do dir
            path = joinpath(dir, "legacy.h5")
            # Write through the canonical writer, then rewrite the attribute
            save_spectral_scan(spec, wl, path;
                description = "legacy", duration_seconds = 1.0)
            h5open(path, "r+") do fid
                a = attributes(fid)
                delete_attribute(fid, "scan_type")
                a["scan_type"] = "spectral"
            end
            r = load_scan(path)
            @test r isa LoadedSpectralResult
            @test r.wavelengths ≈ wl
        end
    end

    @testset "format version validation" begin
        trace = _mock_trace(5)

        # Helper: save a valid kinetic file, then overwrite its format tag
        function _with_format_tag(dir, tag)
            path = joinpath(dir, "tagged.h5")
            save_kinetic_scan(trace, path; description = "tagged")
            h5open(path, "r+") do fid
                delete_attribute(fid, "format")
                attributes(fid)["format"] = tag
            end
            path
        end

        mktempdir() do dir
            # (a) Future MAJOR version: informative error naming both versions
            path = _with_format_tag(dir, "QPSDrive/2.0")
            err = try
                load_scan(path)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("2.0", err.msg)          # the file's version
            @test occursin("QPSDrive/1.0", err.msg) # what this reader supports

            # (b) Same-major future MINOR version: loads, but warns
            path = _with_format_tag(dir, "QPSDrive/1.99")
            r = @test_logs (:warn, r"newer") match_mode=:any load_scan(path)
            @test r isa LoadedScanResult
            @test r.trace.signal ≈ trace.signal

            # (c) Missing format attribute (non-QPSScanFormat HDF5 file):
            # informative error, not a raw KeyError
            alien = joinpath(dir, "alien.h5")
            h5open(alien, "w") do fid
                fid["unrelated"] = [1.0, 2.0, 3.0]
            end
            err = try
                load_scan(alien)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("format", err.msg)

            # (d) Unparseable format tag: informative error too
            path = _with_format_tag(dir, "SomeOtherTool/3.1")
            err = try
                load_scan(path)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("SomeOtherTool/3.1", err.msg)
        end
    end

    @testset "corrupt and truncated files" begin
        trace = _mock_trace(64)
        sweeps = _mock_sweeps(64, 4)

        mktempdir() do dir
            # Truncated HDF5: keep only the first half of a valid file's bytes.
            # load_scan must throw a catchable, informative ErrorException —
            # not a segfault or a cryptic libhdf5 internal.
            path = joinpath(dir, "good.h5")
            save_kinetic_scan(trace, path; sweeps = sweeps, description = "whole")
            bytes = read(path)
            tpath = joinpath(dir, "truncated.h5")
            write(tpath, bytes[1:div(length(bytes), 2)])

            err = try
                load_scan(tpath)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin(tpath, err.msg)
            @test occursin("truncated or corrupt", err.msg)

            # Missing required dataset: clear error naming the missing path
            mpath = joinpath(dir, "missing_dataset.h5")
            save_kinetic_scan(trace, mpath; sweeps = sweeps, description = "whole")
            h5open(mpath, "r+") do fid
                HDF5.delete_object(fid["data"], "time_ps")
            end
            err = try
                load_scan(mpath)
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin(mpath, err.msg)
            @test occursin("time_ps", err.msg)

            # Nonexistent path: clear error, not an HDF5 open failure
            err = try
                load_scan(joinpath(dir, "does_not_exist.h5"))
                nothing
            catch e
                e
            end
            @test err isa ErrorException
            @test occursin("not found", err.msg)
        end
    end

    @testset "update_scan_description! / update_scan_comment! / update_scan_sample_name!" begin
        trace = _mock_trace(5)
        mktempdir() do dir
            path = joinpath(dir, "rename.h5")
            save_kinetic_scan(trace, path;
                description = "before",
                comment = "old comment",
                scan_params = Dict{String,Any}("metadata" => Dict{String,Any}()),
            )

            update_scan_description!(path, "after")
            update_scan_comment!(path, "new comment")
            update_scan_sample_name!(path, "test-sample")

            r = load_scan(path)
            @test r.description == "after"
            @test r.comment == "new comment"
            @test r.scan_params["metadata"]["sample_name"] == "test-sample"

            # Empty string clears
            update_scan_sample_name!(path, "")
            r2 = load_scan(path)
            @test r2.scan_params["metadata"]["sample_name"] == ""
        end
    end

    @testset "writer rejects non-HDF5 path" begin
        trace = _mock_trace(3)
        @test_throws ErrorException save_kinetic_scan(trace, "foo.csv")
    end
end
