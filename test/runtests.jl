using Test
using Dates
using HDF5
using OpticalSpectroscopy
using QPSScanFormat

# Helpers for building fixtures
function _mock_trace(npts=10)
    time_ps = collect(range(-1.0, 5.0; length=npts))
    signal = sin.(time_ps)
    TATrace(time_ps, signal)
end

function _mock_spectrum(npts=8)
    wl = collect(range(2000.0, 2200.0; length=npts))  # nm
    wn = QPSScanFormat.wl_to_wn.(wl)
    signal = randn(npts)
    TASpectrum(wn, signal), wl
end

function _mock_sweeps(n_points=10, n_sweeps=3)
    X = randn(n_points, n_sweeps)
    Y = randn(n_points, n_sweeps)
    DC = ones(n_points, n_sweeps)
    SweepData(X, Y, DC)
end

@testset "QPSScanFormat" begin

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
            @test r.trace.time ≈ trace.time
            @test r.sweeps isa SweepData
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
            @test r.spectrum.wavenumber ≈ QPSScanFormat.wl_to_wn.(wl)
            @test r.description == "test spectrum"
            @test r.sweeps isa SweepData
            @test r.scan_params["delay_ps"] ≈ 1.5
        end
    end

    @testset "broadband round-trip" begin
        time_ps = collect(range(-2.0, 10.0; length=5))
        wl_nm = collect(range(1900.0, 2100.0; length=4))
        data = randn(5, 4)
        mat = TAMatrix(time_ps, wl_nm, data)

        mktempdir() do dir
            path = joinpath(dir, "broadband.h5")
            save_broadband_scan(mat, path;
                description = "test broadband",
                metadata = Dict{String,Any}("sample_name" => "MoS2"),
            )

            r = load_scan(path)
            @test r isa TAMatrix
            @test r.time ≈ time_ps
            @test r.wavelength ≈ wl_nm
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
