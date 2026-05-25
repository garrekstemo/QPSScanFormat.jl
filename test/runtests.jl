using Test
using QPSScanFormat

@testset "QPSScanFormat" begin
    @testset "smoke" begin
        @test isdefined(QPSScanFormat, :QPSScanFormat)
    end

    # Round-trip tests added in Phase 3 once read/write moves over.
end
